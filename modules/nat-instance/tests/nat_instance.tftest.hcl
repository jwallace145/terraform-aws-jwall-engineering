mock_provider "aws" {
  # Computed and unset unless the module sets it: a route that targeted the
  # instance would carry the instance's ID here instead.
  mock_resource "aws_route" {
    defaults = {
      instance_id = ""
    }
  }
}

variables {
  name                    = "databricks-poc-nat"
  subnet_id               = "subnet-0123456789abcdef0"
  private_route_table_ids = ["rtb-0123456789abcdef0", "rtb-0123456789abcdef1"]
  source_cidrs            = ["10.0.2.0/24", "10.0.3.0/24"]
  ami_id                  = "ami-0123456789abcdef0"
}

run "routes_target_eni" {
  command = apply

  assert {
    condition     = length(aws_route.default) == 2
    error_message = "expected one default route per private route table"
  }

  assert {
    condition = alltrue([
      for r in aws_route.default :
      r.destination_cidr_block == "0.0.0.0/0" && r.network_interface_id == aws_network_interface.this.id && r.instance_id == ""
    ])
    error_message = "routes must target the ENI (network_interface_id), never instance_id"
  }
}

run "eni_disables_source_dest_check" {
  command = plan


  assert {
    condition     = aws_network_interface.this.source_dest_check == false
    error_message = "the NAT ENI must have source_dest_check disabled"
  }

  assert {
    condition     = aws_network_interface.this.subnet_id == "subnet-0123456789abcdef0"
    error_message = "the ENI must sit in subnet_id"
  }

  assert {
    condition     = one(aws_instance.this.primary_network_interface).network_interface_id == aws_network_interface.this.id
    error_message = "the instance must use the ENI as its primary interface"
  }
}

run "one_elastic_ip_on_eni" {
  command = plan


  assert {
    condition     = aws_eip.this.domain == "vpc"
    error_message = "the Elastic IP must be a VPC address"
  }

  assert {
    condition     = aws_eip.this.network_interface == aws_network_interface.this.id
    error_message = "the Elastic IP must target the NAT ENI"
  }

  assert {
    condition     = aws_eip.this.tags["Name"] == "databricks-poc-nat" && aws_eip.this.tags["Component"] == "nat-instance"
    error_message = "the Elastic IP must carry Name and Component"
  }
}

run "security_group_ingress_only_from_sources" {
  command = plan

  assert {
    condition     = length(aws_security_group.this.ingress) == 1
    error_message = "expected one ingress rule"
  }

  assert {
    condition     = toset(one(aws_security_group.this.ingress).cidr_blocks) == toset(var.source_cidrs)
    error_message = "ingress must come only from source_cidrs"
  }

  assert {
    condition     = !contains(flatten([for i in aws_security_group.this.ingress : i.cidr_blocks]), "0.0.0.0/0")
    error_message = "no ingress from 0.0.0.0/0"
  }

  assert {
    condition     = one(aws_security_group.this.ingress).protocol == "-1" && one(aws_security_group.this.egress).protocol == "-1"
    error_message = "all protocols in and out"
  }
}

run "user_data_is_cloud_config" {
  command = plan

  assert {
    condition     = startswith(aws_instance.this.user_data, "#cloud-config\n")
    error_message = "user data must be a #cloud-config document"
  }

  assert {
    condition = (
      one([for f in yamldecode(trimprefix(aws_instance.this.user_data, "#cloud-config\n")).write_files : f if f.path == "/usr/local/sbin/nat-setup.sh"]).permissions == "0755"
    )
    error_message = "write_files must write /usr/local/sbin/nat-setup.sh with mode 0755"
  }

  assert {
    condition = (
      one([for f in yamldecode(trimprefix(aws_instance.this.user_data, "#cloud-config\n")).write_files : f if f.path == "/usr/local/sbin/nat-setup.sh"]).content == file("${path.module}/files/nat-setup.sh")
    )
    error_message = "the written script must be files/nat-setup.sh"
  }

  assert {
    condition = (
      yamldecode(trimprefix(aws_instance.this.user_data, "#cloud-config\n")).runcmd == [["/usr/local/sbin/nat-setup.sh", "10.0.2.0/24", "10.0.3.0/24"]]
    )
    error_message = "runcmd must invoke the script with every source CIDR"
  }

  assert {
    condition     = aws_instance.this.user_data_replace_on_change == true
    error_message = "user data changes must replace the instance"
  }
}

run "imdsv2_required" {
  command = plan

  assert {
    condition     = one(aws_instance.this.metadata_options).http_tokens == "required"
    error_message = "IMDSv2 must be required"
  }
}

run "root_volume_encrypted_gp3" {
  command = plan

  assert {
    condition = (
      one(aws_instance.this.root_block_device).encrypted == true &&
      one(aws_instance.this.root_block_device).volume_type == "gp3" &&
      one(aws_instance.this.root_block_device).volume_size == 8
    )
    error_message = "root volume must be an encrypted 8 GB gp3"
  }
}

run "rejects_x86_instance_type" {
  command = plan

  variables {
    instance_type = "t3.nano"
  }

  expect_failures = [var.instance_type]
}

run "rejects_empty_route_tables" {
  command = plan

  variables {
    private_route_table_ids = []
  }

  expect_failures = [var.private_route_table_ids]
}
