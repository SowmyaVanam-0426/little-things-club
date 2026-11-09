terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "ap-southeast-2"
}
data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}
resource "aws_instance" "web_instance" {
  ami                         = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type               = "t8i.micro"
  key_name                    = aws_key_pair.datacenter_kp.key_name
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.wb_dg.id]
  subnet_id                   = aws_subnet.public_subnet1.id
  iam_instance_profile        = aws_iam_instance_profile.webapp_profile.name
  user_data                   = <<-EOF
  #!/bin/bash

  apt-get update -y
  apt-get install -y nginx awscli

  mkdir -p /var/www/html

  for i in {1..5}; do
    if aws s3 sync s3://${aws_s3_bucket.webapp_bucket.bucket}/ /var/www/html/ --region ap-southeast-2; then
        break
    fi
    sleep 10
done

  cat <<'NGINX' > /etc/nginx/sites-available/default
  server {
      listen 80;
      server_name _;

      root /var/www/html;
      index index.html;

      location / {
          try_files $uri $uri/ =404;
      }
  }
  NGINX

  nginx -t
  systemctl enable nginx
  systemctl restart nginx
EOF

  depends_on = [
    aws_s3_object.webapp_files,
    aws_iam_role_policy_attachment.s3_attach
  ]

  tags = {
    Name = "Little Things Club Web Server"
  }
}

# Create the key pair
resource "tls_private_key" "datacenter_kp" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair
resource "aws_key_pair" "datacenter_kp" {
  key_name   = "datacenter-kp"
  public_key = tls_private_key.datacenter_kp.public_key_openssh
}

# Save the private key to file
resource "local_file" "private_key" {
  content         = tls_private_key.datacenter_kp.private_key_pem
  filename        = "/home/lenovo/Downloads/little-things-club-static-website/key/datacenter-kp.pem"
  file_permission = "0400"
}

# Output the key pair name (optional)
output "key_pair_name" {
  value = aws_key_pair.datacenter_kp.key_name
}

resource "aws_vpc" "webapp_vpc" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_subnet" "public_subnet1" {
  vpc_id            = aws_vpc.webapp_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-southeast-2a"

  tags = {
    Name = "three_public_sb1"
  }
}
#security group for the web application

resource "aws_security_group" "wb_dg" {
  name        = "webapp_sg"
  description = "Allow SSH"
  vpc_id      = aws_vpc.webapp_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["Public IP Address/32"] # Replace with your actual public IP address
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

resource "aws_internet_gateway" "igw_wb" {
  vpc_id = aws_vpc.webapp_vpc.id

  tags = {
    Name = "webapp_igw"
  }

}

resource "aws_route_table" "webapp_rt" {
  vpc_id = aws_vpc.webapp_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw_wb.id
  }
}

resource "aws_route_table_association" "public_subnet1_association" {
  subnet_id      = aws_subnet.public_subnet1.id
  route_table_id = aws_route_table.webapp_rt.id
}

#s3 bucket for the web application

resource "aws_s3_bucket" "webapp_bucket" {
  bucket = "little-things-club-static-782gtw"
}

resource "aws_s3_object" "webapp_files" {
  for_each = fileset("${path.module}/webapp", "**")

  bucket = aws_s3_bucket.webapp_bucket.id
  key    = each.value
  source = "${path.module}/webapp/${each.value}"
  etag   = filemd5("${path.module}/webapp/${each.value}")
}
resource "aws_s3_bucket_public_access_block" "webapp_bucket" {
  bucket                  = aws_s3_bucket.webapp_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
# EC2 trust policy
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# IAM role
resource "aws_iam_role" "s3_role" {
  name               = "LittleThingsClub-EC2-S3-Role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

# S3 read permissions
resource "aws_iam_policy" "s3_read" {
  name = "LittleThingsClub-S3-Read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.webapp_bucket.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.webapp_bucket.arn}/*"
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "s3_attach" {
  role       = aws_iam_role.s3_role.name
  policy_arn = aws_iam_policy.s3_read.arn
}

# Instance profile//update the instance profile to use the IAM role
resource "aws_iam_instance_profile" "webapp_profile" {
  name = "LittleThingsClub-EC2-Profile"
  role = aws_iam_role.s3_role.name
}
