terraform {
  required_providers {
      aws = {
      source = "hashicorp/aws"
      version = "4.0.0"
    }
  }
  required_version = "~> 1.6.6"
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = "true"
  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
   filter {
   name = "virtualization-type"
   values = ["hvm"]
  }
  owners = ["099720109477"]
}

resource "aws_vpc" "my_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_hostnames = true
  tags = {
    Name = "my_vpc"
  }
}

resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id
  tags = {
    Name = "my_igw"
  }
}

// Create a group of public subnets based on the variable subnet_count.public
resource "aws_subnet" "my_public_subnet" {
  // count is the number of resources we want to create
  count = var.subnet_count.public
 
  // Put the subnet into the "my_vpc" VPC
  vpc_id = aws_vpc.my_vpc.id
  
  // We are grabbing a CIDR block from the "public_subnet_cidr_blocks" variable
  // since it is a list, we need to grab the element based on count,
  // since count is 1, we will be grabbing the first cidr block 
  // which is going to be 10.0.1.0/24
  cidr_block = var.public_subnet_cidr_blocks[count.index]
  
  // We are grabbing the availability zone from the data object we created earlier
  // Since this is a list, we are grabbing the name of the element based on count
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "my_public_subnet_${count.index}"
  }
}

resource "aws_subnet" "my_private_subnet" {
  count = var.subnet_count.private
  vpc_id = aws_vpc.my_vpc.id
  cidr_block = var.private_subnet_cidr_blocks[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name = "my_private_subnet_${count.index}"
  }
}

resource "aws_route_table" "my_public_rt" {
  // Put the route table in the "my_vpc" VPC
  vpc_id = aws_vpc.my_vpc.id

  // Since this is the public route table, it will need
  // access to the internet. So we are adding a route with
  // a destination of 0.0.0.0/0 and targeting the Internet
  // Gateway "my_igw"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }
}

// Here we are going to add the public subnets to the 
// "my_public_rt" route table
resource "aws_route_table_association" "public" {
  count = var.subnet_count.public
  route_table_id = aws_route_table.my_public_rt.id
  
  // This is the subnet ID. Since the "my_public_subnet" is a 
  // list of the public subnets, we need to use count to grab the
  // subnet element and then grab the id of that subnet
  subnet_id = aws_subnet.my_public_subnet[count.index].id
}

resource "aws_route_table" "my_private_rt" {
  vpc_id = aws_vpc.my_vpc.id

  // Since this is going to be a private route table, 
  // we will not be adding a route
}

// Here we are going to add the private subnets to the
// route table "my_private_rt"
resource "aws_route_table_association" "private" {
  count = var.subnet_count.private
  route_table_id = aws_route_table.my_private_rt.id
  subnet_id = aws_subnet.my_private_subnet[count.index].id
}

resource "aws_security_group" "my_web_sg" {
  name = "my_web_sg"
  description = "Security group for my web server"
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    description = "Allow all traffic through HTTP"
    from_port = "80"
    to_port = "80"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "Allow SSH"
    from_port = "22"
    to_port = "22"
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "my_web_sg"
  }
}

resource "aws_security_group" "my_db_sg" {
  name = "my_db_sg"
  description = "Security group for database"
  vpc_id = aws_vpc.my_vpc.id
  ingress {
    description = "Allow MySQL traffic from only the web sg"
    from_port = "3306"
    to_port = "3306"
    protocol = "tcp"
    security_groups = [aws_security_group.my_web_sg.id]
  }
  tags = {
    Name = "my_db_sg"
  }
}

resource "aws_db_subnet_group" "my_db_subnet_group" {
  name = "my_db_subnet_group"
  description = "DB subnet group"
  
  // Since the db subnet group requires 2 or more subnets, we are going to
  // loop through our private subnets in "my_private_subnet" and
  // add them to this db subnet group
  subnet_ids  = [for subnet in aws_subnet.my_private_subnet : subnet.id]
}

resource "aws_db_instance" "my_database" {
  allocated_storage = var.settings.database.allocated_storage
  engine = var.settings.database.engine
  engine_version = var.settings.database.engine_version
  instance_class = var.settings.database.instance_class
  db_name = var.settings.database.db_name
  username = var.db_username
  password = var.db_password
  db_subnet_group_name  = aws_db_subnet_group.my_db_subnet_group.id
  vpc_security_group_ids = [aws_security_group.my_db_sg.id]
  // This refers to the skipping final snapshot of the database. It is a 
  // boolean that is set by the settings.database.skip_final_snapshot
  // variable, which is currently set to true.
  skip_final_snapshot = var.settings.database.skip_final_snapshot
}

resource "aws_key_pair" "ssh_key" {
  key_name   = "ssh-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_instance" "my_web" {
  count = var.settings.web_app.count
  ami = data.aws_ami.ubuntu.id
  instance_type = var.settings.web_app.instance_type
  subnet_id = aws_subnet.my_public_subnet[count.index].id
  key_name = aws_key_pair.ssh_key.key_name
  vpc_security_group_ids = [aws_security_group.my_web_sg.id]
  tags = {
    Name = "my_web_${count.index}"
  }
  user_data = file("docker.sh")
}

// Create an Elastic IP for each EC2 instance
resource "aws_eip" "my_web_eip" {
  count = var.settings.web_app.count
  instance = aws_instance.my_web[count.index].id
  vpc = true
  tags = {
    Name = "my_web_eip_${count.index}"
  }
}

locals {
  dashboard_config = <<-EOT
    # my production config file
    MYSQL_USER = "${var.db_username}"
    MYSQL_PASSWORD = "${var.db_password}"
    MYSQL_HOST = "${aws_db_instance.my_database.address}"
    MYSQL_DB = "${var.settings.database.db_name}"
    BASIC_AUTH_USERNAME = "${var.app_username}"
    BASIC_AUTH_PASSWORD ="${var.app_password}"
    BASIC_AUTH_FORCE = True
  EOT
}

resource "local_file" "dashboard_config" {
    filename = var.app_config_file
    content  = local.dashboard_config
}

resource "null_resource" "copy_file_on_vm" {
  depends_on = [
    aws_instance.my_web,
    local_file.dashboard_config
  ]

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host = aws_eip.my_web_eip[0].public_ip
  }

  provisioner "file" {
    source = var.app_config_file      // terraform machine
    destination = "config.py" // remote machine
  }
}

resource "null_resource" "exec_run_app" {
  depends_on = [
    aws_instance.my_web,
    null_resource.copy_file_on_vm
  ]

  connection {
    type = "ssh"
    user = "ubuntu"
    private_key = file("~/.ssh/id_rsa")
    host = aws_eip.my_web_eip[0].public_ip
  }

  provisioner "remote-exec" {
    inline = [
          "sudo docker run --name dashboard --restart always --detach --publish 80:5000 -v ./config.py:/app/config.py ghcr.io/anasalamero/dashboard:latest",
        ]
  }
}
