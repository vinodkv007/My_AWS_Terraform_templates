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


# Create a public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"  # Change to your desired AZ
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

# Associate the subnet with the route table
resource "aws_route_table_association" "example" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.example.id
}


# Create a security group for your web app
resource "aws_security_group" "web_app" {
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

# Launch an EC2 instance for your web app
resource "aws_instance" "web_app_instance" {
  ami           = "ami-04cb4ca688797756f"  # Replace with your desired AMI ID
  instance_type = "t2.micro"           # Change to your desired instance type
  subnet_id     = aws_subnet.public.id
  security_groups = [aws_security_group.web_app.id]

  # You can add user data or provisioners for configuration here
  user_data = <<-EOF
              #!/bin/bash
              # Install a web server (e.g., Apache)
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              EOF
}

# Output the public IP address of the EC2 instance
output "web_app_public_ip" {
  value = aws_instance.web_app_instance.public_ip
}
