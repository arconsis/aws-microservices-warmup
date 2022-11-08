##########################
# Security Group
##########################
resource "aws_security_group" "this" {

  name        = var.sg_name
  description = var.description
  vpc_id      = var.vpc_id
  tags        = {
    Name = "${var.sg_name}-aws-warmup-sg"
    VPC  = var.vpc_id
  }
}

#####################################
# Security Group Ingress Rules
#####################################

# SG rules with ingress_cidr_blocks
resource "aws_security_group_rule" "ingress_cidr_rules" {
  for_each          = var.ingress_cidr_rules
  security_group_id = aws_security_group.this.id
  type              = "ingress"

  cidr_blocks      = each.value.cidr_blocks
  ipv6_cidr_blocks = each.value.ipv6_cidr_blocks
  description      = each.value.description

  from_port = each.value.from_port
  to_port   = each.value.to_port
  protocol  = each.value.protocol
}

# SG rules with ingress_source_security_group_id
resource "aws_security_group_rule" "ingress_source_sg_rules" {
  for_each          = var.ingress_source_sg_rules
  security_group_id = aws_security_group.this.id
  type              = "ingress"

  description = each.value.description

  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  source_security_group_id = each.value.source_security_group_id
}

#####################################
# Security Group Egress Rules
#####################################

# SG rules with egress_cidr_blocks
resource "aws_security_group_rule" "egress_cidr_rules" {
  for_each          = var.egress_cidr_rules
  security_group_id = aws_security_group.this.id
  type              = "egress"

  cidr_blocks      = each.value.cidr_blocks
  ipv6_cidr_blocks = each.value.ipv6_cidr_blocks
  description      = each.value.description

  from_port = each.value.from_port
  to_port   = each.value.to_port
  protocol  = each.value.protocol
}

# SG rules with egress_source_security_group_id
resource "aws_security_group_rule" "egress_source_sg_rules" {
  for_each          = var.egress_source_sg_rules
  security_group_id = aws_security_group.this.id
  type              = "egress"

  description = each.value.description

  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  source_security_group_id = each.value.source_security_group_id
}
