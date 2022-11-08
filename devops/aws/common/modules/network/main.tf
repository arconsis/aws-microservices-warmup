################################################################################
# VPC Definition
################################################################################
resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_support               = var.enable_dns_support
  enable_dns_hostnames             = var.enable_dns_hostnames

  tags = {
    Name = "aws-warmup-vpc"
  }
}

################################################################################
# Availability zones
################################################################################

data "aws_availability_zones" "available" {
  state = "available"
}

################################################################################
# IG Definition
################################################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = {
    Name = "aws-warmup-ig"
  }
}

################################################################################
# Subnets Definition
################################################################################

resource "aws_subnet" "public" {
  count = var.public_subnet_count

  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  cidr_block      = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index)
  ipv6_cidr_block = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index)

  tags = merge(
    var.public_subnet_additional_tags,
    {
      Name   = "aws-warmup-public-subnet"
      Role   = "public"
      VPC    = aws_vpc.this.id
      Subnet = data.aws_availability_zones.available.names[count.index]
    }
  )
}

resource "aws_subnet" "private" {
  count = var.private_subnet_count

  vpc_id            = aws_vpc.this.id
  availability_zone = data.aws_availability_zones.available.names[count.index]

  cidr_block = cidrsubnet(aws_vpc.this.cidr_block, 4, count.index + var.public_subnet_count)

  tags = merge(
    var.private_subnet_additional_tags, {
      Name   = "aws-warmup-public-subnet"
      Role   = "private"
      VPC    = aws_vpc.this.id
      Subnet = data.aws_availability_zones.available.names[count.index]
    }
  )
}

################################################################################
# NAT Definition
################################################################################

# Create a NAT gateway with an Elastic IP for each private subnet to get internet connectivity
resource "aws_eip" "nat" {
  count = var.private_subnet_count

  vpc = true

  tags = {
    Name   = "aws-warmup-eip"
    Role   = "private"
    VPC    = aws_vpc.this.id
    Subnet = element(aws_subnet.public.*.id, count.index)
  }

}

resource "aws_nat_gateway" "ngw" {
  count = var.private_subnet_count

  allocation_id = element(aws_eip.nat.*.id, count.index)
  subnet_id     = element(aws_subnet.public.*.id, count.index)

  tags = {
    Name   = "aws-warmup-ngw"
    Role   = "private"
    VPC    = aws_vpc.this.id
    Subnet = element(aws_subnet.public.*.id, count.index)
  }

  depends_on = [aws_internet_gateway.igw]
}

################################################################################
# Route Tables, Routes and Associations
################################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "aws-warmup-public-rt"
    Role = "public"
    VPC  = aws_vpc.this.id
  }
}

resource "aws_route" "public" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public" {
  count          = var.public_subnet_count
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

# Create a new route table for the private subnets, make it route non-local traffic through the NAT gateway to the internet
resource "aws_route_table" "private" {
  count  = var.private_subnet_count
  vpc_id = aws_vpc.this.id

  tags = {
    Name   = "aws-warmup-private-rt"
    Role   = "private"
    VPC    = aws_vpc.this.id
    Subnet = element(aws_subnet.private.*.id, count.index)
  }
}

resource "aws_route" "private" {
  count                  = var.private_subnet_count
  route_table_id         = element(aws_route_table.private.*.id, count.index)
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = element(aws_nat_gateway.ngw.*.id, count.index)
}

# Explicitly associate the newly created route tables to the private subnets (so they don't default to the main route table)
resource "aws_route_table_association" "private" {
  count          = var.private_subnet_count
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}
