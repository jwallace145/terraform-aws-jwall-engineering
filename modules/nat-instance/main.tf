locals {
  tags = {
    Name      = var.name
    Component = var.component
  }

  # Cloud-init writes the script and runs it with the source CIDRs as arguments.
  user_data = join("\n", [
    "#cloud-config",
    yamlencode({
      write_files = [{
        path        = "/usr/local/sbin/nat-setup.sh"
        permissions = "0755"
        owner       = "root:root"
        content     = file("${path.module}/files/nat-setup.sh")
      }]
      runcmd = [concat(["/usr/local/sbin/nat-setup.sh"], var.source_cidrs)]
    }),
  ])
}

data "aws_subnet" "this" {
  id = var.subnet_id
}

resource "aws_security_group" "this" {
  name        = var.name
  description = "NAT instance: all traffic in from the private source CIDRs, all out"
  vpc_id      = data.aws_subnet.this.vpc_id

  ingress {
    description = "All traffic from the private source CIDRs"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = var.source_cidrs
  }

  egress {
    description = "All traffic out"
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# The ENI outlives the instance: routes point at it, so replacing the instance
# keeps routing alive.
resource "aws_network_interface" "this" {
  subnet_id         = var.subnet_id
  security_groups   = [aws_security_group.this.id]
  source_dest_check = false
  description       = "${var.name} NAT interface"

  tags = local.tags
}

# An interface created separately never gets an auto-assigned public IPv4, so
# the NAT's egress address is an Elastic IP on the ENI.
resource "aws_eip" "this" {
  domain            = "vpc"
  network_interface = aws_network_interface.this.id

  tags = local.tags
}

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type

  primary_network_interface {
    network_interface_id = aws_network_interface.this.id
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    tags        = local.tags
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = local.tags

  depends_on = [aws_eip.this]
}

resource "aws_route" "default" {
  for_each = toset(var.private_route_table_ids)

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_network_interface.this.id
}
