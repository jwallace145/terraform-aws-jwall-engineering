output "network_interface_id" {
  description = "ID of the NAT's network interface, the target of the default routes. Replacing the instance creates a new one, and the routes follow in the same apply."
  value       = aws_instance.this.primary_network_interface_id
}

output "instance_id" {
  description = "ID of the NAT instance."
  value       = aws_instance.this.id
}

output "security_group_id" {
  description = "ID of the NAT's security group."
  value       = aws_security_group.this.id
}

output "public_ip" {
  description = "Auto-assigned public IPv4 address that private traffic leaves from (it changes when the instance is replaced), for allow-lists at the destination."
  value       = aws_instance.this.public_ip
}
