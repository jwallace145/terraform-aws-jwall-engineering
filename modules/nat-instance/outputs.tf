output "network_interface_id" {
  description = "ID of the NAT's network interface, the target of the default routes. It survives replacement of the instance."
  value       = aws_network_interface.this.id
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
  description = "Elastic IP address that private traffic leaves from, for allow-lists at the destination."
  value       = aws_eip.this.public_ip
}
