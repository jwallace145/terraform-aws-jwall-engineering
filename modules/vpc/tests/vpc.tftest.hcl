mock_provider "aws" {
  override_during = plan

  mock_resource "aws_vpc" {
    defaults = {
      id = "vpc-0123"
    }
  }
}

variables {
  name = "jwall-engineering-rusty-chess"
}

run "vpc_basics" {
  command = plan

  assert {
    condition = (
      aws_vpc.this.cidr_block == "10.0.0.0/16" &&
      aws_vpc.this.enable_dns_support == true &&
      aws_vpc.this.enable_dns_hostnames == true
    )
    error_message = "the VPC must use the default CIDR with DNS support and hostnames on"
  }

  assert {
    condition     = aws_vpc.this.tags == tomap({ Name = "jwall-engineering-rusty-chess", Component = "vpc" })
    error_message = "the VPC must carry Name and Component tags only"
  }
}

run "two_public_subnets" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "one public subnet per availability zone"
  }

  assert {
    condition = (
      aws_subnet.public[0].cidr_block == "10.0.0.0/24" &&
      aws_subnet.public[1].cidr_block == "10.0.1.0/24"
    )
    error_message = "subnets must be consecutive /24s carved from the VPC CIDR"
  }

  assert {
    condition = (
      aws_subnet.public[0].availability_zone == "us-east-1a" &&
      aws_subnet.public[1].availability_zone == "us-east-1b"
    )
    error_message = "subnets must follow the availability_zones list in order"
  }

  assert {
    condition     = aws_subnet.public[0].map_public_ip_on_launch == true && aws_subnet.public[1].map_public_ip_on_launch == true
    error_message = "public subnets assign public IPs on launch"
  }

  assert {
    condition     = aws_subnet.public[0].tags == tomap({ Name = "jwall-engineering-rusty-chess-public-us-east-1a", Component = "vpc" })
    error_message = "subnets are named <name>-public-<az>"
  }
}

run "internet_route" {
  command = plan

  assert {
    condition     = aws_route.internet.destination_cidr_block == "0.0.0.0/0"
    error_message = "the public route table must default-route to the internet gateway"
  }

  assert {
    condition     = length(aws_route_table_association.public) == 2
    error_message = "every public subnet must be associated with the public route table"
  }

  assert {
    condition = (
      aws_internet_gateway.this.tags == tomap({ Name = "jwall-engineering-rusty-chess-igw", Component = "vpc" }) &&
      aws_route_table.public.tags == tomap({ Name = "jwall-engineering-rusty-chess-public", Component = "vpc" })
    )
    error_message = "the gateway and route table carry Name and Component tags"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      length(output.public_subnet_ids) == 2 &&
      output.vpc_id == "vpc-0123" &&
      output.cidr_block == "10.0.0.0/16"
    )
    error_message = "outputs must describe the VPC and its public subnets"
  }
}

run "one_az" {
  command = plan

  variables {
    availability_zones = ["us-east-1a"]
  }

  assert {
    condition     = length(aws_subnet.public) == 1 && length(output.public_subnet_ids) == 1
    error_message = "one availability zone gives one subnet"
  }
}

run "rejects_bad_cidr" {
  command = plan

  variables {
    cidr_block = "10.0.0.0/8"
  }

  expect_failures = [var.cidr_block]
}

run "rejects_bad_az" {
  command = plan

  variables {
    availability_zones = ["eu-west-1a"]
  }

  expect_failures = [var.availability_zones]
}
