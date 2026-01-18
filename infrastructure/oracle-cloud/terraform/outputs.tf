###############################################################################
# Outputs for Oracle Cloud Infrastructure (WebRTC-Lite)
###############################################################################

output "infrastructure_summary" {
  description = "Summary of provisioned infrastructure"
  value = {
    project_name       = var.project_name
    environment        = var.environment
    region             = var.region
    turn_server_ip     = oci_core_instance.turn_server.public_ip
    turn_server_domain = var.turn_domain_name
  }
}

output "connection_info" {
  description = "Connection information"
  value = {
    ssh_command     = "ssh -i ${var.ssh_public_key_path} ubuntu@${oci_core_instance.turn_server.public_ip}"
    stun_port       = "3478"
    turn_tls_port   = "5349"
    api_port        = "8080"
  }
}

output "next_steps" {
  description = "Next steps after provisioning"
  value = [
    "1. Update DNS: ${var.turn_domain_name} -> ${oci_core_instance.turn_server.public_ip}",
    "2. SSH to server: ssh -i ${var.ssh_public_key_path} ubuntu@${oci_core_instance.turn_server.public_ip}",
    "3. Run setup script: sudo bash /opt/webrtc-lite/setup.sh",
    "4. Configure Firebase Firestore with provided rules",
    "5. Test STUN/TURN connectivity",
  ]
}

output "security_info" {
  description = "Security information"
  value = {
    firewall_ports = ["22 (SSH)", "80 (HTTP)", "443 (HTTPS)", "3478 (STUN)", "5349 (TURNS)"]
    authentication = "HMAC-SHA1 with time-limited credentials"
    encryption    = "TLS 1.3 for signaling, DTLS-SRTP for media"
  }
}
