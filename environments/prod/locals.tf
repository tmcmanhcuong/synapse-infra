locals {
  name_prefix = "${var.project}-${var.environment}"

  azs = [
    "${var.aws_region}a",
    "${var.aws_region}b",
  ]
}
