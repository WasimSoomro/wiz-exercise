data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = var.name
  cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets  = ["10.0.0.0/24", "10.0.1.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Project = var.name
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# IAM role for Mongo EC2 (intentionally overly permissive)
resource "aws_iam_role" "mongo_ec2_role" {
  name = "mongo-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Attach overly permissive policy (intentional misconfiguration)
resource "aws_iam_role_policy_attachment" "mongo_admin_attach" {
  role       = aws_iam_role.mongo_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

# Instance profile (EC2 requires this)
resource "aws_iam_instance_profile" "mongo_instance_profile" {
  name = "mongo-instance-profile"
  role = aws_iam_role.mongo_ec2_role.name
}

# Security Group for Mongo EC2 (intentionally insecure SSH)
resource "aws_security_group" "mongo_sg" {
  name        = "mongo-security-group"
  description = "Security group for Mongo EC2"
  vpc_id      = module.vpc.vpc_id

  # SSH open to the world (intentional misconfiguration)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Mongo only accessible from inside VPC
  ingress {
    description = "Mongo from VPC only"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mongo-sg"
  }
}

# Ubuntu 20.04 AMI (intentionally older distro version)
data "aws_ami" "ubuntu_20_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical official images (mitigate supply chain risk)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "mongo" {
  ami                         = data.aws_ami.ubuntu_20_04.id
  instance_type               = "t3.micro"
  subnet_id                   = module.vpc.public_subnets[0] # pick first public subnet / receive public IP through IG
  vpc_security_group_ids      = [aws_security_group.mongo_sg.id]
  associate_public_ip_address = true                                                 # SSH exposed to internet
  key_name                    = var.mongo_key_name                                   # Attach EC2 key pair named in mongo_key_name
  iam_instance_profile        = aws_iam_instance_profile.mongo_instance_profile.name # Attach IAM permissions

  user_data = <<-EOF
#!/bin/bash
set -euxo pipefail



apt-get update -y
apt-get install -y curl gnupg

curl -fsSL https://pgp.mongodb.com/server-4.4.asc | gpg --dearmor -o /usr/share/keyrings/mongodb-server-4.4.gpg

echo "deb [signed-by=/usr/share/keyrings/mongodb-server-4.4.gpg] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" > /etc/apt/sources.list.d/mongodb-org-4.4.list

apt-get update -y
apt-get install -y mongodb-org
apt-get install -y mongodb-database-tools

systemctl enable mongod
systemctl start mongod

sed -i 's/^  bindIp:.*$/  bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl restart mongod

mongo --eval 'db.getSiblingDB("admin").createUser({user:"admin",pwd:"Password123!",roles:[{role:"root",db:"admin"}]})' || true

if ! grep -q "authorization: enabled" /etc/mongod.conf; then
  printf "\nsecurity:\n  authorization: enabled\n" >> /etc/mongod.conf
fi

systemctl restart mongod
EOF


}

resource "random_id" "bucket_id" {
  byte_length = 4
}

resource "aws_s3_bucket" "mongo_backups" {
  bucket        = "sandbox-mongo-backups-${random_id.bucket_id.hex}"
  force_destroy = true

}

resource "aws_s3_bucket_public_access_block" "mongo_backups" {
  bucket = aws_s3_bucket.mongo_backups.id

  block_public_acls       = false #ACL false keeps it fully permissive
  ignore_public_acls      = false #ACL false keeps it fully permissive
  block_public_policy     = false #attach a public bucket policy
  restrict_public_buckets = false #allows bucket to be public
}

resource "aws_s3_bucket_policy" "mongo_backups_public" {
  bucket = aws_s3_bucket.mongo_backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Public listing of the bucket, applies to bucket ARN
      {
        Sid       = "PublicListBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:ListBucket"]
        Resource  = [aws_s3_bucket.mongo_backups.arn]
      },
      # Public read of all objects
      {
        Sid       = "PublicReadObjects"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject"]
        Resource  = ["${aws_s3_bucket.mongo_backups.arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "mongo_s3_full_access" {
  role       = aws_iam_role.mongo_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
