locals {
  az1 = "${var.region}a"
  az2 = "${var.region}b"

  fqdn = "${var.dns_hostname}.${var.dns_zonename}"
}