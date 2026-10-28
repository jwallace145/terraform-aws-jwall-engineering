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
