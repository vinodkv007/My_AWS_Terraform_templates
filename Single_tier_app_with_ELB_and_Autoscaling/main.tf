# Initialize the AWS provider
provider "aws" {
  region = "us-east-1"  # Change to your desired region
}

# Create a VPC
resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

# Internet Gateway
resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}  


# Create a public subnet-1
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"  # Change to your desired AZ
  map_public_ip_on_launch = true
}


# Create a public subnet-2
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"  # Change to your desired AZ
  map_public_ip_on_launch = true
}


#Route table
resource "aws_route_table" "example" {
  vpc_id = aws_vpc.example.id
}

# Create a new route in the route table
resource "aws_route" "example" {
  route_table_id         = aws_route_table.example.id
  destination_cidr_block = "0.0.0.0/0"  # Destination CIDR block (e.g., default route)
  gateway_id             = aws_internet_gateway.example.id  # Replace with your Internet Gateway ID
}

# Associate the public subnet-1 with the route table
resource "aws_route_table_association" "rta_for_subnet_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.example.id
}

# Associate the public subnet-2 with the route table
resource "aws_route_table_association" "rta_for_subnet_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.example.id
}


# Create a security group for your web app
resource "aws_security_group" "web_app_sg" {
  name        = "web-app-sg"
  description = "Security group for the web app"
  vpc_id      = aws_vpc.example.id

  # Define your ingress rules here (e.g., allow HTTP traffic)
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

#aws launch configuration
resource "aws_launch_configuration" "web_server_lc" {
  name_prefix                 = "web-server-lc-"
  image_id                    = "ami-04cb4ca688797756f" # Replace with your desired AMI ID
  instance_type               = "t2.micro"           # Replace with your desired instance type

  security_groups             = [aws_security_group.web_app_sg.id]
  user_data                   = <<-EOF
                                #!/bin/bash
                                # Install a web server (e.g., Apache)
                                sudo yum update -y
                                sudo yum install -y httpd
                                sudo systemctl start httpd
                                sudo systemctl enable httpd
                                sudo chkconfig httpd on
                                instance_id=$(ec2-metadata --instance-id | cut -d " " -f 2)
                                public_ip=$(ec2-metadata --public-ipv4 | cut -d " " -f 2)
                                az=$(ec2-metadata --availability-zone| cut -d " " -f 2)
                                echo "<html><head><title>My Public IP</title></head><body><h1>Availability zone: $az</h1><h1> Instance id: $instance_id</h1><h1>Public IP Address: $public_ip</h1></body></html>" | sudo tee /var/www/html/index.html
                               EOF
  lifecycle {
    create_before_destroy = true
  }
}

#aws autoscaling group-1 in public subnet-1
resource "aws_autoscaling_group" "web_server_asg_1" {
  name                      = "web-server-asg-1"
  launch_configuration      = aws_launch_configuration.web_server_lc.name
  min_size                  = 2     # Minimum number of instances
  max_size                  = 5     # Maximum number of instances
  desired_capacity          = 2     # Desired number of instances
  vpc_zone_identifier       = aws_subnet.public_1[*].id
  termination_policies      = ["OldestInstance"]

  target_group_arns = [aws_lb_target_group.tg_1.arn]
}

#aws autoscaling group-2 in public subnet-2 
resource "aws_autoscaling_group" "web_server_asg_2" {
  name                      = "web-server-asg-2"
  launch_configuration      = aws_launch_configuration.web_server_lc.name
  min_size                  = 2     # Minimum number of instances
  max_size                  = 5     # Maximum number of instances
  desired_capacity          = 2     # Desired number of instances
  vpc_zone_identifier       = aws_subnet.public_2[*].id
  termination_policies      = ["OldestInstance"]

  target_group_arns = [aws_lb_target_group.tg_2.arn]
}


# Create an Elastic Load Balancer (ELB)

resource "aws_lb" "example" {
  name               = "example-lb"
  internal           = false
  load_balancer_type = "application"
  #subnets            = aws_subnet.public[*].id
  subnets            = [aws_subnet.public_1.id, aws_subnet.public_2.id]
  security_groups    = [aws_security_group.web_app_sg.id]

  enable_http2 = true
  enable_cross_zone_load_balancing = true

  enable_deletion_protection = false

  tags = {
    Name = "example-lb"
  }
}

# Create target group-1 for the Auto Scaling Group
resource "aws_lb_target_group" "tg_1" {
  name     = "tg-1"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id
  health_check {
    path = "/"
  }
}


# Create target group-2 for the Auto Scaling Group
resource "aws_lb_target_group" "tg_2" {
  name     = "tg-2"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.example.id
  health_check {
    path = "/"
  }
}

# Attach the target group-1 and target group-2 to the ELB listener and distribute traffic equally among them
resource "aws_lb_listener" "listener_1" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn = aws_lb_target_group.tg_1.arn
        weight           = 50
      }

      target_group {
        arn = aws_lb_target_group.tg_2.arn
        weight           = 50
      }
    }
  }
}
