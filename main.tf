
//Main VPC
resource "aws_vpc" "MYVPC" {
  cidr_block = var.Main_Cidr
  enable_dns_hostnames = true
  tags = {
    Name = "${var.Project}vpc"
  }
}
//InternetGateway
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.MYVPC.id
  tags = {
    Name = "${var.Project}igw"
  }
}


// subnet
resource "aws_subnet" "Subnet" {
  vpc_id = aws_vpc.MYVPC.id
  count = length(local.selected_azs) * var.subnet_per_az 
  availability_zone = element(local.selected_azs, floor(count.index / var.subnet_per_az) )


  cidr_block =  cidrsubnet(var.Main_Cidr,4, count.index)
  map_public_ip_on_launch = count.index % var.subnet_per_az == 0
  

  tags = {
    Name = "${var.Project} ${count.index % var.subnet_per_az == 0 ? "public" : "private" } _Subnet${count.index+1}"
  }
  
}



//Elastic ip
resource "aws_eip" "EIP" {
  count = length(local.private_subnet_ids)
  tags = {
    Name = "${var.Project}Nat_EIP"
  }
}
//NatGateway
resource "aws_nat_gateway" "Nat" {
    count = length(local.private_subnet_ids)
    allocation_id = aws_eip.EIP[count.index].id
    subnet_id = element(local.public_subnet_ids, count.index)
    tags = {
    Name = "${var.Project}NAT ${count.index+1} "
  }
}
//public route table
resource "aws_route_table" "Public_RT" {
  vpc_id = aws_vpc.MYVPC.id
  tags = {
    Name = "${var.Project}Public_RT"
  }
}
resource "aws_route" "Public_R1" {
  route_table_id = aws_route_table.Public_RT.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.IGW.id
}
resource "aws_route_table_association" "RT_public" {
  count = length(local.public_subnet_ids)
  subnet_id = local.public_subnet_ids[count.index]
  route_table_id = aws_route_table.Public_RT.id
}


//private route table
resource "aws_route_table" "Private_RT" {
  count = length(local.private_subnet_ids)
  vpc_id = aws_vpc.MYVPC.id
  tags = {
    Name = "${var.Project}Private_RT ${count.index}"
  }
}
resource "aws_route" "Private_R1" {
  count = length(local.private_subnet_ids)
  route_table_id = aws_route_table.Private_RT[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.Nat[count.index].id
}
resource "aws_route_table_association" "RT_private" {
  count = length(local.private_subnet_ids)
  subnet_id = local.private_subnet_ids[count.index]
  route_table_id = aws_route_table.Private_RT[count.index].id
}
//custom rule 
resource "aws_iam_policy" "custom_ec2_ssm_policy" {
  name        = "${var.Project}CustomEC2SSMPolicy"
  description = "Custom policy for EC2 to access SSM"
  policy      = jsonencode({
    "Version" = "2012-10-17"
    "Statement" = [
      {
        "Effect" = "Allow"
        "Action" = [
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ec2messages:AcknowledgeMessage",
          "ec2messages:DeleteMessage",
          "ec2messages:FailMessage",
          "ec2messages:GetEndpoint",
          "ec2messages:GetMessages",
          "ec2messages:SendReply",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:DeleteLogGroup",
          "logs:DeleteLogStream",
          "logs:PutDestination",
          "logs:PutDestinationPolicy",
          "logs:DescribeDestinations",
          "logs:DescribeExportTasks",
          "logs:CreateExportTask",
          "logs:DescribeSubscriptionFilters",
          "logs:PutSubscriptionFilter",
          "logs:DeleteSubscriptionFilter",
          "logs:DescribeMetricFilters",
          "logs:DescribeLogStreams",
          "logs:PutMetricFilter",
          "logs:DeleteMetricFilter"
        ]
        "Resource" = "*"
      }
    ]
  })
}

//Iam role Who can access the role
resource "aws_iam_role" "EC2_SSM" {
  name               = "${var.Project}EC2_SSM"
  assume_role_policy = data.aws_iam_policy_document.instance_assume_role_policy.json

  tags = {
    Name = "${var.Project} EC2 SSM Role"
  }
}
//we attach to the rule the policy and permissions that it needs
resource "aws_iam_role_policy_attachment" "ec2_ssm_policy" {
  role       = aws_iam_role.EC2_SSM.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"   
}
//create Iam profile
resource "aws_iam_instance_profile" "ec2_ssm_instance_profile" {
  name = "${var.Project}-ec2-instance-profile" 
  role = aws_iam_role.EC2_SSM.name 
  tags = { 
    Name = "${var.Project} EC2 Instance Profile" 
    }
}

//Target Group
resource "aws_lb_target_group" "WebTG" {
  name        = "${var.Project}WebTG"
  target_type = "instance"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.MYVPC.id
  

  health_check {
    path                = "/"
    interval            = 5    # Minimum interval time in seconds
    timeout             = 2    # Minimum timeout in seconds
    healthy_threshold   = 2    # Minimum number of successes before considering the target healthy
    unhealthy_threshold = 2    # Minimum number of failures before considering the target unhealthy
  }
}



//Security Group for target group
resource "aws_security_group" "ALBSG" {
  name        = "${var.Project}ALBSG"
  description = "Allow TLS inbound traffic and all outbound traffic"
  vpc_id      = aws_vpc.MYVPC.id

  tags = {
    Name = "${var.Project}ALBSG"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allow_tls_ipv4" {
  security_group_id = aws_security_group.ALBSG.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "allow_all_traffic_ipv4" {
  security_group_id = aws_security_group.ALBSG.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}

//laod balancer
resource "aws_lb" "LB" {
  name               = "${var.Project}LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ALBSG.id]
  subnets = local.public_subnet_ids
  //subnets = local.public_subnet_ids
  //subnets            = [for subnet in aws_subnet.public : subnet.id]
  //enable_deletion_protection = true

  tags = {
    Name = "${var.Project}LB"
    Environment = "production"
  }
}
//associate Load balancer with target group
resource "aws_lb_listener" "HTTP_80" {
  load_balancer_arn = aws_lb.LB.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.WebTG.arn
  }
}

// a launch template
resource "aws_launch_template" "web_launch_template" {
  name          = "${var.Project}WebLaunchTemplate"
  instance_type = "t2.micro"
  image_id      = var.ami

  vpc_security_group_ids = [aws_security_group.ALBSG.id]

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd

              # Fetching the IMDSv2 token
              TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

              # Fetching instance ID and region using the token
              INSTANCE_ID=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)
              REGION=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/placement/region)
              AZ=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/placement/availability-zone)

              echo "This is an app server in AWS Region: $${REGION},Region: $${AZ}, Instance ID: $${INSTANCE_ID}" > /var/www/html/index.html
              EOF
  )

  tags = {
    Name = "${var.Project}WebLaunchTemplate"
  }
}


//autoscaling_group
resource "aws_autoscaling_group" "ASG" {
  launch_template {
    id      = aws_launch_template.web_launch_template.id
    version = "$Latest"
  }

  vpc_zone_identifier = local.private_subnet_ids

  min_size           = 1
  max_size           = 4
  desired_capacity   = 2
  target_group_arns  = [aws_lb_target_group.WebTG.arn]
  health_check_type  = "ELB"
  health_check_grace_period = 300
  tag {
    key = "Name"
    value = "${var.Project}ASG-instance"
    propagate_at_launch = true 
  }

}

output "load_balancer_dns_name" {
  description = "The DNS name of the Load Balancer"
  value       = aws_lb.LB.dns_name
}



output "instance_ids" {
  depends_on = [aws_autoscaling_group.ASG]
  description = "The instance IDs of the Auto Scaling Group"
  value = data.aws_instances.asg_instances.ids
}

# output "zones" {
  
#   value = element(data.aws_availability_zones.available.names, 2)
# }



# //public instances
# resource "aws_instance" "public_instance" {
#   count = length(local.public_subnet_ids)
#   ami = var.ami
#   instance_type = "t2.micro"
#   iam_instance_profile = aws_iam_instance_profile.ec2_ssm_instance_profile.id
#   subnet_id = element(local.public_subnet_ids, count.index)
#    tags = {
#     Name = "${var.Project}public_instance ${count.index+1} "
#   }
# }

# //private instances
# resource "aws_instance" "private_instance" {
#   count = length(local.private_subnet_ids)
#   ami = var.ami
#   instance_type = "t2.micro"
#   iam_instance_profile = aws_iam_instance_profile.ec2_ssm_instance_profile.id
#   subnet_id = local.private_subnet_ids[count.index]
#   tags = {
#     Name = "${var.Project}private_instance ${count.index+1} "
#   }
# }

# //associate a target group with an EC2 instance
# resource "aws_lb_target_group_attachment" "TGA" {
#   count = length(local.private_subnet_ids)
#   target_group_arn = aws_lb_target_group.WebTG.arn
#   target_id        = aws_instance.private_instance[count.index].id
#   port             = 80
# }