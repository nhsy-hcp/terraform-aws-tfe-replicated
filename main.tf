data "http" "myip" {
  url = "https://ipinfo.io/ip"
}

# aws ec2 describe-images --owners 309956199498 --query 'sort_by(Images, &CreationDate)[*].[CreationDate,Name,ImageId]' --filters "Name=name,Values=RHEL-7*" --region eu-west-1 --output table --include-deprecated
data "aws_ami" "rhel_79" {
  most_recent        = true
  owners             = ["309956199498"]
  include_deprecated = true

  filter {
    name   = "name"
    values = ["RHEL-7.9_HVM-2021*"]
    #values = ["RHEL-7.9_HVM_GA*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}


locals {
  mypublicip = "${chomp(data.http.myip.response_body)}/32"
}

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.tag_prefix}-vpc"
  }
}

resource "aws_subnet" "public1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone = local.az1
  tags = {
    Name = "${var.tag_prefix}-public"
  }
}

resource "aws_subnet" "private1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 11)
  availability_zone = local.az1
  tags = {
    Name = "${var.tag_prefix}-private"
  }
}

resource "aws_subnet" "private2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, 12)
  availability_zone = local.az2
  tags = {
    Name = "${var.tag_prefix}-private"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.tag_prefix}-gw"
  }
}

resource "aws_route_table" "publicroutetable" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.tag_prefix}-route-table-gw"
  }
}

resource "aws_route_table_association" "PublicRT1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.publicroutetable.id
}



resource "aws_security_group" "default-sg" {
  vpc_id      = aws_vpc.main.id
  name        = "${var.tag_prefix}-sg"
  description = "${var.tag_prefix}-sg"

  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["${local.mypublicip}", "${aws_eip.default.public_ip}/32"]
  }

  ingress {
    description = "netdata listening"
    from_port   = 19999
    to_port     = 19999
    protocol    = "tcp"
    cidr_blocks = ["${local.mypublicip}"] #"0.0.0.0/0"
  }

  ingress {
    description = "ssh from private ip"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${local.mypublicip}"] #"0.0.0.0/0"
  }

  ingress {
    description = "replicated dashboard from internet"
    from_port   = 8800
    to_port     = 8800
    protocol    = "tcp"
    cidr_blocks = ["${local.mypublicip}"]
  }

  ingress {
    description = "postgresql from internal"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.tag_prefix}-tfe_sg"
  }
}

resource "aws_s3_bucket" "tfe" {
  bucket        = "${var.tag_prefix}-bucket"
  force_destroy = true

  tags = {
    Name = "${var.tag_prefix}-bucket"
  }
}

resource "aws_s3_bucket_versioning" "tfe-bucket-versioning" {
  bucket = aws_s3_bucket.tfe.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "software" {
  bucket        = "${var.tag_prefix}-software"
  force_destroy = true

  tags = {
    Name = "${var.tag_prefix}-software"
  }
}


resource "aws_s3_object" "object_license" {
  bucket = aws_s3_bucket.software.id
  key    = var.filename_license
  source = "files/${var.filename_license}"

  # depends_on = [
  #   aws_s3_bucket.tfe-bucket-software
  # ]

}

# resource "aws_s3_bucket_acl" "tfe-bucket" {
#   bucket = aws_s3_bucket.tfe-bucket.id
#   acl    = "private"
# }

resource "aws_iam_role" "role" {
  name = "${var.tag_prefix}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.tag_prefix}-instance"
  role = aws_iam_role.role.name
}

resource "aws_iam_role_policy" "policy" {
  name = "${var.tag_prefix}-bucket"
  role = aws_iam_role.role.id

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:DeleteObject",
          "s3:GetBucketLocation"
        ],
        "Resource" : [
          "arn:aws:s3:::${var.tag_prefix}-bucket",
          "arn:aws:s3:::${var.tag_prefix}-software",
          "arn:aws:s3:::*/*"
        ]
      },
      {
        "Sid" : "VisualEditor1",
        "Effect" : "Allow",
        "Action" : "s3:ListAllMyBuckets",
        "Resource" : "*"
      },
      {
        "Sid" : "VisualEditor2",
        "Effect" : "Allow",
        "Action" : "pricing:*",
        "Resource" : "*"
      }
    ]
  })
}

# code idea from https://itnext.io/lets-encrypt-certs-with-terraform-f870def3ce6d
data "aws_route53_zone" "base_domain" {
  name = var.dns_zonename
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "registration" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = var.certificate_email
}

resource "acme_certificate" "certificate" {
  account_key_pem = acme_registration.registration.account_key_pem
  common_name     = "${var.dns_hostname}.${var.dns_zonename}"

  dns_challenge {
    provider = "route53"

    config = {
      AWS_HOSTED_ZONE_ID = data.aws_route53_zone.base_domain.zone_id
    }
  }

  depends_on = [acme_registration.registration]
}

resource "aws_s3_object" "certificate_artifacts_s3_objects" {
  for_each = toset(["certificate_pem", "issuer_pem", "private_key_pem"])

  bucket  = aws_s3_bucket.software.id
  key     = each.key # TODO set your own bucket path
  content = lookup(acme_certificate.certificate, "${each.key}")
}

data "aws_route53_zone" "default" {
  name         = var.dns_zonename
  private_zone = false
}

resource "aws_route53_record" "default" {
  zone_id = data.aws_route53_zone.default.zone_id
  name    = var.dns_hostname
  type    = "A"
  ttl     = "300"
  records = [aws_eip.default.public_ip]
}

resource "aws_network_interface" "default" {
  subnet_id   = aws_subnet.public1.id
  private_ips = [cidrhost(cidrsubnet(var.vpc_cidr, 8, 1), 22)]

  tags = {
    Name = "primary_network_interface"
  }
}

resource "aws_network_interface_sg_attachment" "default" {
  security_group_id    = aws_security_group.default-sg.id
  network_interface_id = aws_network_interface.default.id
}

resource "aws_eip" "default" {
  vpc = true

  # instance                  = aws_instance.tfe_server.id
  associate_with_private_ip = aws_network_interface.default.private_ip
  depends_on                = [aws_internet_gateway.gw]

  tags = {
    Name = "${var.tag_prefix}-eip"
  }
}

resource "aws_eip_association" "default" {
  instance_id   = aws_instance.default.id
  allocation_id = aws_eip.default.id
}

resource "aws_ebs_volume" "swap" {
  availability_zone = local.az1
  size              = 32
  # default is the gp2 disk
  # type              = "gp2"
  # faster disks is the IOPS version
  type = "io2"
  iops = 1000
}

resource "aws_ebs_volume" "docker" {
  availability_zone = local.az1
  size              = 100
  # default is the gp2 disk
  # type              = "gp2"
  # faster disks is the IOPS version
  type = "io2"
  iops = 2000
}

resource "aws_key_pair" "default" {
  key_name   = "${var.tag_prefix}-key"
  public_key = var.ssh_public_key
}

resource "aws_instance" "default" {
  ami           = data.aws_ami.rhel_79.id #var.ami
  instance_type = "t3.2xlarge"
  key_name      = aws_key_pair.default.key_name

  network_interface {
    network_interface_id = aws_network_interface.default.id
    device_index         = 0
  }

  root_block_device {
    volume_size = 50
    volume_type = "io1"
    iops        = 1000
  }

  iam_instance_profile = aws_iam_instance_profile.profile.name

  user_data = templatefile("${path.module}/scripts/cloudinit_tfe_server.yaml", {
    tag_prefix           = var.tag_prefix
    filename_license     = var.filename_license
    dns_hostname         = var.dns_hostname
    tfe_password         = var.tfe_password
    dns_zonename         = var.dns_zonename
    pg_dbname            = aws_db_instance.default.db_name
    pg_address           = aws_db_instance.default.address
    rds_password         = var.rds_password
    tfe_bucket           = aws_s3_bucket.tfe.id
    tfe_private_ip       = aws_network_interface.default.private_ip
    tfe_public_ip        = aws_eip.default.public_ip
    software_bucket      = aws_s3_bucket.software.id
    region               = var.region
    tfe_release_sequence = var.tfe_release_sequence
  })

  tags = {
    Name = "${var.tag_prefix}-tfe"
  }

  depends_on = [
    aws_network_interface_sg_attachment.default, aws_db_instance.default
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_put_response_hop_limit = 2
  }
}

resource "aws_volume_attachment" "swap" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.swap.id
  instance_id = aws_instance.default.id
}

resource "aws_volume_attachment" "docker" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.docker.id
  instance_id = aws_instance.default.id
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.tag_prefix}-main"
  subnet_ids = [aws_subnet.private1.id, aws_subnet.private2.id]

  tags = {
    Name = "DB subnet group"
  }
}

resource "aws_db_instance" "default" {
  allocated_storage           = 10
  engine                      = "postgres"
  engine_version              = "14.10" #"12.8"
  instance_class              = "db.t3.large"
  username                    = "postgres"
  password                    = var.rds_password
  parameter_group_name        = "default.postgres14"
  skip_final_snapshot         = true
  db_name                     = "tfe"
  publicly_accessible         = false
  vpc_security_group_ids      = [aws_security_group.default-sg.id]
  db_subnet_group_name        = aws_db_subnet_group.default.name
  identifier                  = "${var.tag_prefix}-rds"
  allow_major_version_upgrade = true
  tags = {
    "Name" = "${var.tag_prefix}-rds"
  }

  # depends_on = [
  #   aws_s3_object.certificate_artifacts_s3_objects
  # ]
}

resource "null_resource" "default" {

  # Changes to tfe instance requires re-provisioning
  triggers = {
    instance_id = aws_instance.default.id
  }

  connection {
    host        = aws_eip.default.public_ip
    type        = "ssh"
    user        = "ec2-user"
    private_key = file(var.ssh_private_key_file)
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo Pausing for cloudinit completion...",
      "while [ ! -f /var/log/cloudinit_complete ]; do sleep 10; done",
      "sleep 60",
      "sudo systemctl stop replicated*",
      "sudo rm -rf /var/lib/replicated/",
      "sleep 60",
      # "cd /var/tmp && sudo ./configure_server.sh",
      # "cd /var/tmp && sudo ./download_and_unpack_software.sh",
      "cd /var/tmp && sudo ./install_tfe.sh",
    ]
  }

  provisioner "local-exec" {
    when    = create
    command = "while ! curl -ksfS --connect-timeout 5 https://${local.fqdn}:8800/dashboard; do sleep 30; done"
  }

  # provisioner "local-exec" {
  #   when    = create
  #   command = "while ! curl -ksfS --connect-timeout 5 https://${local.fqdn}/_health_check?full=1; do sleep 30; done"
  # }

  depends_on = [
    aws_instance.default,
    aws_db_instance.default
  ]
}