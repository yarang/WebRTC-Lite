###############################################################################
# Variables for Oracle Cloud Infrastructure (WebRTC-Lite)
###############################################################################

variable "project_name" {
  description = "Project name prefix for resources"
  type        = string
  default     = "webrtc-lite"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "prod"
}

###############################################################################
# ORACLE CLOUD CONFIGURATION
###############################################################################

variable "region" {
  description = "Oracle Cloud region"
  type        = string
  default     = "us-ashburn-1"
}

variable "tenancy_ocid" {
  description = "Oracle Cloud tenancy OCID"
  type        = string
}

variable "user_ocid" {
  description = "Oracle Cloud user OCID"
  type        = string
}

variable "compartment_ocid" {
  description = "Oracle Cloud compartment OCID"
  type        = string
}

variable "fingerprint" {
  description = "API key fingerprint"
  type        = string
}

variable "private_key_path" {
  description = "Path to private API key file"
  type        = string
}

###############################################################################
# NETWORK CONFIGURATION
###############################################################################

variable "vcn_cidr" {
  description = "VCN CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "Subnet CIDR block"
  type        = string
  default     = "10.0.1.0/24"
}

###############################################################################
# VM CONFIGURATION (Free Tier)
###############################################################################

variable "vm_shape" {
  description = "VM shape (Free Tier: VM.Standard.E2.1.Micro)"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "vm_ocpus" {
  description = "Number of OCPUs (Free Tier: up to 0.1)"
  type        = number
  default     = 0.1
}

variable "vm_memory" {
  description = "Memory in GB (Free Tier: 1GB)"
  type        = number
  default     = 1
}

###############################################################################
# SSH CONFIGURATION
###############################################################################

variable "ssh_public_key_path" {
  description = "Path to SSH public key"
  type        = string
}

###############################################################################
# TURN SERVER CONFIGURATION
###############################################################################

variable "turn_domain_name" {
  description = "Domain name for TURN server (for Let's Encrypt)"
  type        = string
  default     = "turn.example.com"
}

variable "letsencrypt_email" {
  description = "Email for Let's Encrypt certificate"
  type        = string
  default     = "admin@example.com"
}

###############################################################################
# STORAGE CONFIGURATION
###############################################################################

variable "logs_volume_size" {
  description = "Size of logs volume in GB"
  type        = number
  default     = 50
}

###############################################################################
# TERRAFORM CONFIGURATION
###############################################################################

variable "state_file" {
  description = "Path to Terraform state file"
  type        = string
  default     = "terraform.tfstate"
}
