resource "random_id" "vpc_display_id" {
    byte_length = 4
}
# ------------------------------------------------------
# VPC
# ------------------------------------------------------
resource "aws_vpc" "main" { 
    cidr_block = "10.0.0.0/16"
    tags = {
        Name = "realtime-dwh-vpc-main-${random_id.vpc_display_id.hex}"
    }
}
# ------------------------------------------------------
# SUBNETS
# ------------------------------------------------------
resource "aws_subnet" "public_subnets" {
    count = 3
    vpc_id = aws_vpc.main.id
    cidr_block = "10.0.${count.index+1}.0/24"
    map_public_ip_on_launch = true
    tags = {
        Name = "realtime-dwh-public-subnet-${count.index}-${random_id.vpc_display_id.hex}"
    }
}
# ------------------------------------------------------
# IGW
# ------------------------------------------------------
resource "aws_internet_gateway" "igw" { 
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "realtime-dwh-igw-${random_id.vpc_display_id.hex}"
    }
}
# ------------------------------------------------------
# ROUTE TABLE
# ------------------------------------------------------
resource "aws_route_table" "route_table" {
    vpc_id = aws_vpc.main.id
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
    tags = {
        Name = "realtime-dwh-route-table-${random_id.vpc_display_id.hex}"
    }
}
resource "aws_route_table_association" "subnet_associations" {
    count = 3
    subnet_id = aws_subnet.public_subnets[count.index].id
    route_table_id = aws_route_table.route_table.id
}
# ------------------------------------------------------
# SECURITY GROUP
# ------------------------------------------------------
resource "aws_security_group" "postgres_sg" {
    name = "postgres_security_group_${random_id.vpc_display_id.hex}"
    description = "${local.aws_description}"
    vpc_id = aws_vpc.main.id
    egress {
        description = "Allow all outbound."
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    ingress {
        description = "Postgres"
        from_port = 5432
        to_port = 5432
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    ingress {
        description = "SSH"
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    tags = {
        Name = "realtime-dwh-postgres-sg-${random_id.vpc_display_id.hex}"
    }
}
# ------------------------------------------------------
# CUSTOMERS ID AND CLOUDINIT
# ------------------------------------------------------
resource "random_id" "customers_id" {
    count = local.num_postgres_instances
    byte_length = 4
}
data "template_cloudinit_config" "pg_bootstrap_customers" {
    base64_encode = true
    part {
        content_type = "text/x-shellscript"
        content = "${file("scripts/pg_customers_bootstrap.sh")}"
    }
}
# ------------------------------------------------------
# CUSTOMERS INSTANCE
# ------------------------------------------------------
resource "aws_instance" "postgres_customers" {
    count = local.num_postgres_instances
    ami = "ami-0c7478fd229861c57"
    instance_type = local.postgres_instance_shape
    subnet_id = aws_subnet.public_subnets[0].id
    vpc_security_group_ids = ["${aws_security_group.postgres_sg.id}"]
    user_data = "${data.template_cloudinit_config.pg_bootstrap_customers.rendered}"
    tags = {
        Name = "realtime-dwh-postgres-customers-instance-${random_id.customers_id[count.index].hex}"
    }
}
# ------------------------------------------------------
# CUSTOMERS EIP
# ------------------------------------------------------
resource "aws_eip" "postgres_customers_eip" {
    count = local.num_postgres_instances
    vpc = true
    instance = aws_instance.postgres_customers[count.index].id
    tags = {
        Name = "realtime-dwh-postgres-customers-eip-${random_id.customers_id[count.index].hex}"
    }
}
# ------------------------------------------------------
# PRODUCTS ID AND CLOUDINIT
# ------------------------------------------------------
resource "random_id" "products_id" {
    count = local.num_postgres_instances
    byte_length = 4
}
data "template_cloudinit_config" "pg_bootstrap_products" {
    base64_encode = true
    part {
        content_type = "text/x-shellscript"
        content = "${file("scripts/pg_products_bootstrap.sh")}"
    }
}
# ------------------------------------------------------
# PRODUCTS INSTANCE
# ------------------------------------------------------
resource "aws_instance" "postgres_products" {
    count = local.num_postgres_instances
    ami = "ami-0c7478fd229861c57"
    instance_type = local.postgres_instance_shape
    subnet_id = aws_subnet.public_subnets[1].id
    vpc_security_group_ids = ["${aws_security_group.postgres_sg.id}"]
    user_data = "${data.template_cloudinit_config.pg_bootstrap_products.rendered}"
    tags = {
        Name = "realtime-dwh-postgres-products-instance-${random_id.products_id[count.index].hex}"
    }
}
# ------------------------------------------------------
# PRODUCTS EIP
# ------------------------------------------------------
resource "aws_eip" "postgres_products_eip" {
    count = local.num_postgres_instances
    vpc = true
    instance = aws_instance.postgres_products[count.index].id
    tags = {
        Name = "realtime-dwh-postgres-products-eip-${random_id.products_id[count.index].hex}"
    }
}