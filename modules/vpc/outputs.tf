output "vpc_id" {
  description = "VPC ID — passed to modules/eks, modules/rds-mysql, and security group rules"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "VPC CIDR block — used in security group ingress rules"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs — NAT Gateways and internet-facing ALBs"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs — EKS nodes run here; passed to modules/eks"
  value       = module.vpc.private_subnets
}

output "intra_subnet_ids" {
  description = "Intra subnet IDs — RDS only, no internet route; passed to modules/rds-mysql"
  value       = module.vpc.intra_subnets
}

output "private_route_table_ids" {
  description = "Private subnet route table IDs"
  value       = module.vpc.private_route_table_ids
}

output "nat_public_ips" {
  description = "Elastic IP of the NAT Gateway — add to external allow-lists for egress"
  value       = module.vpc.nat_public_ips
}
