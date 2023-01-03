output "ssh_tfe_server" {
  value = "ssh ec2-user@${var.dns_hostname}.${var.dns_zonename}"
}

output "tfe_dashboard" {
  value = "https://${var.dns_hostname}.${var.dns_zonename}:8800"
}

output "tfe_appplication" {
  value = "https://${var.dns_hostname}.${var.dns_zonename}"
}

output "ssh_tfe_server_ip" {
  value = "ssh ec2-user@${aws_eip.tfe-eip.public_ip}"
}
