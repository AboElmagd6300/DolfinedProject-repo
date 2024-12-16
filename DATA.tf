//availability_zones
data "aws_availability_zones" "available" {
  state = "available"
}

//IAM policy
data "aws_iam_policy_document" "instance_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}



data "aws_instances" "asg_instances" {
  filter {
    name   = "tag:Name"
    values = ["${var.Project}ASG"]
  }
}
