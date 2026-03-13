resource "aws_guardduty_detector" "main" {
  enable = true

  tags = {
    Project = var.name
  }
}

resource "aws_accessanalyzer_analyzer" "main" {
  analyzer_name = "${var.name}-analyzer"
  type          = "ACCOUNT"

  tags = {
    Project = var.name
  }
}
