SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV_DIR := environments/prod

.PHONY: help init fmt validate lint plan apply destroy destroy-targeted kubeconfig clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform in environments/prod
	cd $(ENV_DIR) && terraform init

fmt: ## Format all Terraform files
	terraform fmt -recursive

validate: init ## Validate Terraform configuration
	cd $(ENV_DIR) && terraform validate

lint: ## Run tflint against environments/prod
	cd $(ENV_DIR) && tflint --config=../../.tflint.hcl

plan: init ## Generate a Terraform plan
	cd $(ENV_DIR) && terraform plan -out=tfplan

apply: ## Apply a previously generated plan
	cd $(ENV_DIR) && terraform apply tfplan

destroy: ## Destroy all resources in environments/prod
	cd $(ENV_DIR) && terraform destroy

destroy-targeted: ## Destroy compute/data resources, preserving Route53, ACM, and GitHub OIDC
	cd $(ENV_DIR) && terraform destroy \
		-target=module.eks \
		-target=module.karpenter \
		-target=module.rds \
		-target=module.ecr \
		-target=module.secrets_manager \
		-target=module.vpc \
		-target=module.kms \
		-auto-approve

kubeconfig: ## Configure kubectl for the robot-shop EKS cluster
	aws eks update-kubeconfig --name robot-shop --region us-east-1

clean: ## Remove local Terraform artifacts
	rm -rf $(ENV_DIR)/.terraform $(ENV_DIR)/tfplan
