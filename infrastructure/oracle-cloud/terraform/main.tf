###############################################################################
# Terraform Configuration for Oracle Cloud Infrastructure (WebRTC-Lite)
#
# This Terraform configuration provisions Oracle Cloud Free Tier resources
# for the WebRTC-Lite TURN/STUN server.
#
# Requirements: Oracle Cloud Free Tier
# - 2 AMD VMs (always free)
# - 10TB/month network bandwidth
# - 200GB block volume storage
#
# Usage:
#   terraform init
#   terraform plan
#   terraform apply
#
# Requirements: REQ-U001, REQ-U003, REQ-S001, REQ-S003
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

###############################################################################
# PROVIDER CONFIGURATION
###############################################################################

provider "oci" {
  region       = var.region
  tenancy_ocid = var.tenancy_ocid
  user_ocid    = var.user_ocid
  fingerprint  = var.fingerprint
  private_key_path = var.private_key_path
}

###############################################################################
# LOCALS
###############################################################################

locals {
  # Naming convention
  name_prefix = "${var.project_name}-${var.environment}"

  # Availability domains (determined dynamically)
  availability_domains = {
    for ad in data.oci_identity_availability_domains.ads.availability_domains :
    ad.name => ad.name
  }
}

###############################################################################
# DATA SOURCES
###############################################################################

# Get the current compartment
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Get the latest Oracle Linux image
data "oci_core_images" "oracle_linux" {
  compartment_id = var.compartment_ocid
  operating_system = "Oracle Linux"
  shape = var.vm_shape

  filter {
    name   = "display_name"
    values = ["^.*Oracle-Linux-9.*-.*-.*"]
    regex  = true
  }

  sort_by = "TIMECREATED"
  sort_order = "DESC"
}

###############################################################################
# NETWORKING
###############################################################################

# Create VCN
resource "oci_core_vcn" "webrtc_vcn" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-vcn"
  cidr_block     = var.vcn_cidr
  dns_label      = "webrtclite"

  is_ipv6enabled = false
}

# Create Internet Gateway
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-igw"
  vcn_id         = oci_core_vcn.webrtc_vcn.id
  enabled        = true
}

# Create Route Table
resource "oci_core_route_table" "route_table" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-rt"
  vcn_id         = oci_core_vcn.webrtc_vcn.id

  route_rules {
    network_entity_id = oci_core_internet_gateway.igw.id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

# Create Security List
resource "oci_core_security_list" "security_list" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-sl"
  vcn_id         = oci_core_vcn.webrtc_vcn.id

  # Ingress rules
  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 80
      max = 80
    }
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 443
      max = 443
    }
  }

  # STUN/TURN ports
  ingress_security_rules {
    protocol = "17"  # UDP
    source   = "0.0.0.0/0"

    udp_options {
      min = 3478
      max = 3478
    }
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 3478
      max = 3478
    }
  }

  ingress_security_rules {
    protocol = "6"  # TCP
    source   = "0.0.0.0/0"

    tcp_options {
      min = 5349
      max = 5349
    }
  }

  # Egress rules
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

# Create Subnet
resource "oci_core_subnet" "public_subnet" {
  compartment_id      = var.compartment_ocid
  display_name        = "${local.name_prefix}-subnet"
  vcn_id              = oci_core_vcn.webrtc_vcn.id
  cidr_block          = var.subnet_cidr
  route_table_id      = oci_core_route_table.route_table.id
  security_list_ids   = [oci_core_security_list.security_list.id]
  prohibit_public_ip_on_vnic = false

  availability_domain = lookup(local.availability_domains, "AD-1", null)
}

###############################################################################
# COMPUTE INSTANCE (TURN SERVER)
###############################################################################

# Create Instance
resource "oci_core_instance" "turn_server" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-turn-server"
  availability_domain = lookup(local.availability_domains, "AD-1", null)

  shape = var.vm_shape

  shape_config {
    ocpus         = var.vm_ocpus
    memory_in_gbs = var.vm_memory
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  create_vnic_details {
    subnet_id = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    hostname_label = "turnserver"
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
    user_data = base64encode(templatefile("${path.module}/cloud-init.yaml", {
      domain_name = var.turn_domain_name
      email = var.letsencrypt_email
    }))
  }

  timeouts {
    create = "60m"
  }
}

###############################################################################
# STORAGE
###############################################################################

# Create Block Volume for logs
resource "oci_core_volume" "logs_volume" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-logs"
  availability_domain = lookup(local.availability_domains, "AD-1", null)

  size_in_gbs = var.logs_volume_size
}

# Attach volume to instance
resource "oci_core_volume_attachment" "logs_attachment" {
  compartment_id = var.compartment_ocid
  display_name   = "${local.name_prefix}-logs-attach"
  instance_id    = oci_core_instance.turn_server.id
  volume_id      = oci_core_volume.logs_volume.id
  attachment_type = "iscsi"
}

###############################################################################
# OUTPUTS
###############################################################################

output "turn_server_public_ip" {
  description = "Public IP address of the TURN server"
  value       = oci_core_instance.turn_server.public_ip
}

output "turn_server_private_ip" {
  description = "Private IP address of the TURN server"
  value       = oci_core_instance.turn_server.private_ip
}

output "ssh_connection_string" {
  description = "SSH connection string to the TURN server"
  value       = "ssh -i ${var.ssh_public_key_path} ubuntu@${oci_core_instance.turn_server.public_ip}"
}

output "setup_command" {
  description = "Command to run Coturn setup script"
  value       = "ssh -i ${var.ssh_public_key_path} ubuntu@${oci_core_instance.turn_server.public_ip} 'sudo -i'"
}
