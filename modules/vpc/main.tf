# A VPC for workloads that need to reach out and never be reached: public
# subnets only, an internet gateway and one route table. No NAT gateway, no
# private subnets and no VPC endpoints: the only recurring cost is the public
# IPv4 address on each instance. Private subnets or a NAT gateway would be
# additive if a later workload needs them.

locals {
  tags = {
    Name      = var.name
    Component = var.component
  }

  # Public subnets are consecutive /24s carved from the VPC CIDR.
  subnet_newbits = 24 - tonumber(split("/", var.cidr_block)[1])
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.tags
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name}-igw"
    Component = var.component
  }
}

resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr_block, local.subnet_newbits, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name      = "${var.name}-public-${var.availability_zones[count.index]}"
    Component = var.component
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name}-public"
    Component = var.component
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# The default security group AWS creates with every VPC allows all traffic
# between its members. Managing it with no rules makes it inert; workloads
# bring their own security group.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name}-default"
    Component = var.component
  }
}
