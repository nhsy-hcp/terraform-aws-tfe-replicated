output "ssh" {
  value = "ssh ec2-user@${var.dns_hostname}.${var.dns_zonename}"
}

output "admin_url" {
  value = "https://${var.dns_hostname}.${var.dns_zonename}:8800"
}

output "url" {
  value = "https://${var.dns_hostname}.${var.dns_zonename}"
}

output "public_ip" {
  value = aws_eip.default.public_ip
}

output "fqdn" {
  value = local.fqdn
}