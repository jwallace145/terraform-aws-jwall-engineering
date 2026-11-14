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

# Spot capacity is per zone: a task fleet spreads over every zone that offers
# its type. Appending zones adds subnets and leaves the existing ones alone.
run "five_zones_keep_the_first_subnets" {
  command = plan

  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1f"]
  }

  assert {
    condition = (
      length(aws_subnet.public) == 5 &&
      aws_subnet.public[0].cidr_block == "10.0.0.0/24" &&
      aws_subnet.public[1].cidr_block == "10.0.1.0/24" &&
      aws_subnet.public[4].availability_zone == "us-east-1f"
    )
    error_message = "zones append subnets in order without moving the first ones"
  }
}

run "rejects_seven_zones" {
  command = plan

  variables {
    availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c", "us-east-1d", "us-east-1e", "us-east-1f", "us-east-1a"]
  }

  expect_failures = [var.availability_zones]
}

run "defaults_unchanged" {
  command = plan

  assert {
    condition = (
      length(aws_subnet.private) == 0 &&
      length(aws_route_table.private) == 0 &&
      length(aws_route_table_association.private) == 0 &&
      length(aws_vpc_endpoint.s3) == 0
    )
    error_message = "with the new inputs at their defaults no private subnet, route table or endpoint may exist"
  }

  assert {
    condition = (
      length(aws_subnet.public) == 2 &&
      length(aws_route_table_association.public) == 2 &&
      length(output.private_subnet_ids) == 0 &&
      output.private_route_table_id == null &&
      output.s3_endpoint_id == null
    )
    error_message = "the public side is unchanged and the new outputs are empty or null"
  }
}

run "creates_private_subnets" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]
  }

  assert {
    condition = (
      length(aws_subnet.private) == 2 &&
      aws_subnet.private[0].cidr_block == "10.0.128.0/20" &&
      aws_subnet.private[1].cidr_block == "10.0.144.0/20" &&
      aws_subnet.private[0].availability_zone == "us-east-1a" &&
      aws_subnet.private[1].availability_zone == "us-east-1b"
    )
    error_message = "each private subnet takes its CIDR and AZ by index"
  }

  assert {
    condition     = aws_subnet.private[0].map_public_ip_on_launch == false && aws_subnet.private[1].map_public_ip_on_launch == false
    error_message = "private subnets must not assign public IPs"
  }

  assert {
    condition = (
      aws_subnet.private[1].tags == tomap({ Name = "jwall-engineering-rusty-chess-private-us-east-1b", Component = "vpc" }) &&
      aws_route_table.private[0].tags == tomap({ Name = "jwall-engineering-rusty-chess-private", Component = "vpc" })
    )
    error_message = "private subnets are named <name>-private-<az> and carry Component"
  }

  assert {
    condition     = length(aws_route_table.private) == 1 && length(aws_route_table_association.private) == 2
    error_message = "one private route table shared by every private subnet"
  }

  assert {
    condition     = length(aws_vpc_endpoint.s3) == 0 && length(output.private_subnet_ids) == 2
    error_message = "private subnets alone create no endpoint"
  }
}

run "rejects_private_cidr_count_mismatch" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.0.128.0/20"]
  }

  expect_failures = [var.private_subnet_cidrs]
}

run "rejects_private_cidr_outside_vpc" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.1.128.0/20", "10.1.144.0/20"]
  }

  expect_failures = [var.private_subnet_cidrs]
}

run "rejects_private_overlapping_public" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.0.0.0/20", "10.0.144.0/20"]
  }

  expect_failures = [var.private_subnet_cidrs]
}

run "rejects_private_overlapping_each_other" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.0.128.0/20", "10.0.128.0/21"]
  }

  expect_failures = [var.private_subnet_cidrs]
}

run "rejects_endpoint_without_private_subnets" {
  command = plan

  variables {
    s3_gateway_endpoint = { enabled = true }
  }

  expect_failures = [var.s3_gateway_endpoint]
}

run "endpoint_on_private_routes" {
  command = plan

  # Distinct IDs so the test can tell the two route tables apart.
  override_resource {
    target          = aws_route_table.public
    override_during = plan
    values          = { id = "rtb-public" }
  }

  override_resource {
    target          = aws_route_table.private[0]
    override_during = plan
    values          = { id = "rtb-private" }
  }

  override_resource {
    target          = aws_vpc_endpoint.s3[0]
    override_during = plan
    values          = { id = "vpce-0123" }
  }

  variables {
    private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]
    s3_gateway_endpoint  = { enabled = true }
  }

  assert {
    condition = (
      aws_vpc_endpoint.s3[0].vpc_endpoint_type == "Gateway" &&
      aws_vpc_endpoint.s3[0].service_name == "com.amazonaws.us-east-1.s3"
    )
    error_message = "the endpoint must be a Gateway endpoint for S3 in us-east-1"
  }

  assert {
    condition = (
      contains(aws_vpc_endpoint.s3[0].route_table_ids, "rtb-private") &&
      !contains(aws_vpc_endpoint.s3[0].route_table_ids, "rtb-public") &&
      length(aws_vpc_endpoint.s3[0].route_table_ids) == 1
    )
    error_message = "the endpoint must be associated with the private route table only, never the public one"
  }

  assert {
    condition     = output.s3_endpoint_id == "vpce-0123" && output.private_route_table_id == "rtb-private"
    error_message = "the endpoint and private route table IDs are exposed as outputs"
  }
}

run "endpoint_policy_uses_condition_not_principal" {
  command = plan

  variables {
    private_subnet_cidrs = ["10.0.128.0/20", "10.0.144.0/20"]
    s3_gateway_endpoint = {
      enabled = true
      policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:*"
          Resource  = "*"
          Condition = {
            ArnEquals = { "aws:PrincipalArn" = "arn:aws:iam::123456789012:role/databricks-poc-databricks-uc" }
          }
        }]
      })
    }
  }

  assert {
    condition = jsondecode(aws_vpc_endpoint.s3[0].policy) == {
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
        Condition = {
          ArnEquals = { "aws:PrincipalArn" = "arn:aws:iam::123456789012:role/databricks-poc-databricks-uc" }
        }
      }]
    }
    error_message = "the endpoint policy must be passed through unchanged"
  }
}
