provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "default" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.default.id
}

resource "aws_subnet" "public_subnet_az1" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "public_subnet_az2" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_subnet" "app_subnet_az1" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "app_subnet_az2" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_subnet" "data_subnet_az1" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.5.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "data_subnet_az2" {
  vpc_id            = aws_vpc.default.id
  cidr_block        = "10.0.6.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_route_table_association" "public_subnet_association_az1" {
  subnet_id      = aws_subnet.public_subnet_az1.id
  route_table_id = aws_route_table.public_route_table_az1.id
}

resource "aws_route_table_association" "public_subnet_association_az2" {
  subnet_id      = aws_subnet.public_subnet_az2.id
  route_table_id = aws_route_table.public_route_table_az2.id
}

resource "aws_route_table" "public_route_table_az1" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route_table" "public_route_table_az2" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route" "public_route_az1" {
  route_table_id         = aws_route_table.public_route_table_az1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route" "public_route_az2" {
  route_table_id         = aws_route_table.public_route_table_az2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_nat_gateway" "nat_gateway_az1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.data_subnet_az1.id
}

resource "aws_nat_gateway" "nat_gateway_az2" {
  allocation_id = aws_eip.nat_eip_az2.id
  subnet_id     = aws_subnet.data_subnet_az2.id
}

resource "aws_eip" "nat_eip_az1" {
  domain = "vpc"
}

resource "aws_eip" "nat_eip_az2" {
  domain = "vpc"
}

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security group for Application Load Balancer"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group for EC2 instances"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Security group for RDS instances"
  vpc_id      = aws_vpc.default.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
}

resource "aws_db_subnet_group" "data_subnet_group" {
  name       = "data-subnet-group"
  subnet_ids = [
    aws_subnet.data_subnet_az1.id,
    aws_subnet.data_subnet_az2.id,
  ]
}

resource "aws_rds_cluster" "postgres_master" {
  engine                = "aurora-postgresql"
  engine_version        = "14"
  database_name         = "testdb"
  master_username       = "dbuser"
  master_password       = "dbpassword"
  backup_retention_period = 7
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  db_subnet_group_name  = aws_db_subnet_group.data_subnet_group.name
}

resource "aws_rds_cluster_instance" "postgres_master_instance_az1" {
  identifier           = "postgres-master-az1"
  cluster_identifier   = aws_rds_cluster.postgres_master.id
  instance_class       = "db.t3.micro"
  availability_zone    = "us-east-1a"
  engine               = "aurora-postgresql"
}

resource "aws_rds_cluster_instance" "postgres_master_instance_az2" {
  identifier           = "postgres-master-az2"
  cluster_identifier   = aws_rds_cluster.postgres_master.id
  instance_class       = "db.t3.micro"
  availability_zone    = "us-east-1b"
  engine               = "aurora-postgresql"
}

resource "aws_launch_configuration" "app_lc_az1" {
  name_prefix   = "app-lc-az1-"
  image_id      = "ami-053b0d53c279acc90"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.ec2_sg.id,
    aws_security_group.alb_sg.id,
  ]

  user_data = <<-EOT
              #!/bin/bash
              apt-get update
              apt-get upgrade -y
              apt-get install -y git
              apt-get install python3 python3-pip -y
              EOT

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "app_lc_az2" {
  name_prefix   = "app-lc-az2-"
  image_id      = "ami-053b0d53c279acc90"
  instance_type = "t2.micro"
  security_groups = [
    aws_security_group.ec2_sg.id,
    aws_security_group.alb_sg.id,
  ]

  user_data = <<-EOT
              #!/bin/bash
              apt-get update
              apt-get upgrade -y
              apt-get install -y git
              apt-get install python3 python3-pip -y
              EOT

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app_asg_az1" {
  name                 = "app-asg-az1"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.app_lc_az1.name
  vpc_zone_identifier  = [aws_subnet.app_subnet_az1.id]

  tag {
    key                 = "Name"
    value               = "app-instance-az1"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group" "app_asg_az2" {
  name                 = "app-asg-az2"
  min_size             = 1
  max_size             = 3
  desired_capacity     = 1
  launch_configuration = aws_launch_configuration.app_lc_az2.name
  vpc_zone_identifier  = [aws_subnet.app_subnet_az2.id]

  tag {
    key                 = "Name"
    value               = "app-instance-az2"
    propagate_at_launch = true
  }
}

resource "aws_lb" "app_alb" {
  name               = "app-alb"
  internal           = false
  load_balancer_type = "application"
  subnets            = [aws_subnet.app_subnet_az1.id, aws_subnet.app_subnet_az2.id]
  security_groups    = [aws_security_group.alb_sg.id]

  tags = {
    Name = "app-alb"
  }
}

resource "aws_lb_target_group" "app_tg_az1" {
  name     = "app-tg-az1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_target_group" "app_tg_az2" {
  name     = "app-tg-az2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.default.id

  health_check {
    path = "/"
  }
}

resource "aws_lb_listener" "app_listener_az1" {
  load_balancer_arn = aws_lb.app_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg_az1.arn
  }
}

# resource "aws_lb_listener" "app_listener_az2" {
#   load_balancer_arn = aws_lb.app_alb.arn
#   port              = "443"
#   protocol          = "HTTPS"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.app_tg_az2.arn
#   }
# }

resource "aws_route53_zone" "test_zone" {
  name = "sretest.com."
}

resource "aws_route53_record" "app_alias" {
  zone_id = aws_route53_zone.test_zone.zone_id
  name    = "sretest.com"
  type    = "A"

  alias {
    name                   = aws_lb.app_alb.dns_name
    zone_id                = aws_lb.app_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "rds_master_alias" {
  zone_id = aws_route53_zone.test_zone.zone_id
  name    = "postgres-master.sretest.com"
  type    = "CNAME"

  records = [aws_rds_cluster_instance.postgres_master_instance_az1.endpoint]
  ttl     = "300"
}

resource "aws_route53_record" "rds_standby_alias" {
  zone_id = aws_route53_zone.test_zone.zone_id
  name    = "postgres-standby.sretest.com"
  type    = "CNAME"

  records = [aws_rds_cluster_instance.postgres_master_instance_az2.endpoint]
  ttl     = "300"
}
