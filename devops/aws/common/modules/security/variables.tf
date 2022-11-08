variable "vpc_id" {
  description = "The region to use for this module."
}

variable "description" {
  description = "The region to use for this module."
}

variable "sg_name" {
  description = "The region to use for this module."
}

variable "ingress_cidr_rules" {
  type = map(object({
    description      = string
    protocol         = string
    from_port        = number
    to_port          = number
    cidr_blocks      = list(string)
    ipv6_cidr_blocks = list(string)
  }))
}

variable "ingress_source_sg_rules" {
  type = map(object({
    description              = string
    protocol                 = string
    from_port                = number
    to_port                  = number
    source_security_group_id = string
  }))
}

variable "egress_cidr_rules" {
  type = map(object({
    description      = string
    protocol         = string
    from_port        = number
    to_port          = number
    cidr_blocks      = list(string)
    ipv6_cidr_blocks = list(string)
  }))
}

variable "egress_source_sg_rules" {
  type = map(object({
    description              = string
    protocol                 = string
    from_port                = number
    to_port                  = number
    source_security_group_id = string
  }))
}