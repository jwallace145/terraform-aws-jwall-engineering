# A VPC for workloads that need to reach out and never be reached: public
# subnets, an internet gateway and one route table. Private subnets (one
# route table, no default route: the caller adds it) and an S3 gateway
# endpoint on the private table are optional and off by default. No NAT
# gateway is created here. With the defaults the only recurring cost is the
# public IPv4 address on each instance.
#
# The VPC's default security group is left as AWS creates it (members may
# talk to each other, all egress). Nothing is launched into it: workloads
# bring their own group. Adopting it would need IAM rights on a group that
# carries no Project tag yet, which the container/manage policy does not
# grant.

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


# Private subnets are optional and have no default route: the caller adds one
# to the single private route table (for example through a NAT instance's
# network interface). With private_subnet_cidrs empty nothing below exists.
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name      = "${var.name}-private-${var.availability_zones[count.index]}"
    Component = var.component
  }
}

resource "aws_route_table" "private" {
  count = length(var.private_subnet_cidrs) > 0 ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = {
    Name      = "${var.name}-private"
    Component = var.component
  }
}

resource "aws_route_table_association" "private" {
  count = length(var.private_subnet_cidrs)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[0].id
}

# Gateway endpoints add a prefix-list route to the tables they are associated
# with. Only the private table is associated, so same-region S3 traffic from
# private subnets stays off the NAT.
resource "aws_vpc_endpoint" "s3" {
  count = var.s3_gateway_endpoint.enabled ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private[0].id]
  policy            = var.s3_gateway_endpoint.policy

  tags = {
    Name      = "${var.name}-s3"
    Component = var.component
  }
}
