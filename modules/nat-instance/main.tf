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

data "aws_default_tags" "current" {}

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

resource "aws_instance" "this" {
  ami           = var.ami_id
  instance_type = var.instance_type

  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  associate_public_ip_address = true
  source_dest_check           = false

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
    # The provider tags the root volume at launch (TagSpecifications, with the
    # provider default_tags merged in), then makes a second CreateTags call
    # after launch with these block tags alone. The block repeats the default
    # tags so that second call does not drop them.
    tags = merge(data.aws_default_tags.current.tags, local.tags)
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true

  tags = local.tags
}

resource "aws_route" "default" {
  # Keyed by position, not by ID: with the tables created in the same stack the
  # IDs are unknown at plan, and for_each keys must be known.
  for_each = { for i, id in var.private_route_table_ids : tostring(i) => id }

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.this.primary_network_interface_id
}
