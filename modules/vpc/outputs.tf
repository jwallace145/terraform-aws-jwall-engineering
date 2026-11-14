output "vpc_id" {
  description = "ID of the VPC, for security groups."
  value       = aws_vpc.this.id
}

output "cidr_block" {
  description = "IPv4 CIDR of the VPC."
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, in the order of `availability_zones`."
  value       = aws_subnet.public[*].id
}

output "internet_gateway_id" {
  description = "ID of the internet gateway."
  value       = aws_internet_gateway.this.id
}

output "route_table_id" {
  description = "ID of the public route table."
  value       = aws_route_table.public.id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets, in the order of `availability_zones`. Empty without `private_subnet_cidrs`."
  value       = aws_subnet.private[*].id
}

output "private_route_table_id" {
  description = "ID of the private route table, for the caller's default route. Null without `private_subnet_cidrs`."
  value       = one(aws_route_table.private[*].id)
}

output "s3_endpoint_id" {
  description = "ID of the S3 gateway endpoint. Null unless `s3_gateway_endpoint.enabled`."
  value       = one(aws_vpc_endpoint.s3[*].id)
}
