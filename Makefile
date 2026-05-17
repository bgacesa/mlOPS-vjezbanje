SHELL := /bin/bash
.PHONY: help init-infra plan-infra apply-infra destroy-infra \
        get-kubeconfig init-platform plan-platform apply-platform destroy-platform \
        all clean

INFRA_DIR    := terraform/01-infra
PLATFORM_DIR := terraform/02-platform
KEY_NAME     ?= mlops-key
AWS_REGION   ?= eu-central-1
KUBECONFIG   ?= ~/.kube/mlops-config

help:
	@echo "MLOps Vjezba — dostupne komande:"
	@echo ""
	@echo "  Infrastruktura:"
	@echo "    make init-infra       - terraform init za 01-infra"
	@echo "    make plan-infra       - terraform plan za 01-infra"
	@echo "    make apply-infra      - terraform apply za 01-infra"
	@echo "    make destroy-infra    - terraform destroy za 01-infra"
	@echo ""
	@echo "  Kubeconfig:"
	@echo "    make get-kubeconfig   - preuzmi kubeconfig sa EC2 instance"
	@echo ""
	@echo "  Platforma (Helm):"
	@echo "    make init-platform    - terraform init za 02-platform"
	@echo "    make plan-platform    - terraform plan za 02-platform"
	@echo "    make apply-platform   - terraform apply za 02-platform"
	@echo "    make destroy-platform - terraform destroy za 02-platform"
	@echo ""
	@echo "  Sve odjednom:"
	@echo "    make all              - apply-infra + get-kubeconfig + apply-platform"
	@echo ""
	@echo "  Varijable:"
	@echo "    KEY_NAME=$(KEY_NAME)  AWS_REGION=$(AWS_REGION)"

init-infra:
	cd $(INFRA_DIR) && terraform init

plan-infra:
	cd $(INFRA_DIR) && terraform plan -var="key_name=$(KEY_NAME)"

apply-infra:
	cd $(INFRA_DIR) && terraform apply -auto-approve -var="key_name=$(KEY_NAME)"

destroy-infra:
	@echo "PAŽNJA: Ovo će uništiti svu infrastrukturu!"
	@read -p "Jeste li sigurni? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	cd $(INFRA_DIR) && terraform destroy -auto-approve -var="key_name=$(KEY_NAME)"

get-kubeconfig:
	@IP=$$(cd $(INFRA_DIR) && terraform output -raw instance_public_ip); \
	INSTANCE_ID=$$(cd $(INFRA_DIR) && terraform output -raw instance_id); \
	echo "Preuzimam kubeconfig sa $$INSTANCE_ID (SSM — bez SSH keya)..."; \
	COMMAND_ID=$$(aws ssm send-command \
	    --instance-ids "$$INSTANCE_ID" \
	    --document-name "AWS-RunShellScript" \
	    --parameters 'commands=["sudo cat /etc/kubernetes/admin.conf"]' \
	    --region $(AWS_REGION) \
	    --query 'Command.CommandId' --output text); \
	echo "  SSM command ID: $$COMMAND_ID"; \
	sleep 5; \
	mkdir -p ~/.kube; \
	aws ssm get-command-invocation \
	    --command-id "$$COMMAND_ID" \
	    --instance-id "$$INSTANCE_ID" \
	    --region $(AWS_REGION) \
	    --query 'StandardOutputContent' --output text \
	  | sed "s|server: https://.*:6443|server: https://$$IP:6443|" \
	  > $(KUBECONFIG); \
	chmod 600 $(KUBECONFIG); \
	echo "Kubeconfig snimljen na $(KUBECONFIG)"; \
	echo "Pokrenite: export KUBECONFIG=$(KUBECONFIG)"

wait-for-cluster:
	@export KUBECONFIG=$(KUBECONFIG); \
	echo "Čekam da cluster bude spreman..."; \
	until kubectl get nodes 2>/dev/null | grep -q Ready; do \
	    echo "  Still waiting..."; sleep 15; \
	done; \
	echo "Cluster je spreman!"

init-platform:
	cd $(PLATFORM_DIR) && terraform init

plan-platform:
	@export KUBECONFIG=$(KUBECONFIG); \
	cd $(PLATFORM_DIR) && terraform plan \
	    -var="kubeconfig_path=$(KUBECONFIG)"

apply-platform:
	@if [ -z "$$MINIO_ROOT_PASSWORD" ]; then \
	    echo "Postavite: export MINIO_ROOT_PASSWORD=<password>"; exit 1; \
	fi
	@export KUBECONFIG=$(KUBECONFIG); \
	cd $(PLATFORM_DIR) && terraform apply -auto-approve \
	    -var="kubeconfig_path=$(KUBECONFIG)" \
	    -var="minio_root_password=$$MINIO_ROOT_PASSWORD"

destroy-platform:
	@echo "PAŽNJA: Ovo će ukloniti sve Helm release-ove!"
	@read -p "Jeste li sigurni? (yes/no): " confirm && [ "$$confirm" = "yes" ]
	@export KUBECONFIG=$(KUBECONFIG); \
	cd $(PLATFORM_DIR) && terraform destroy -auto-approve \
	    -var="kubeconfig_path=$(KUBECONFIG)" \
	    -var="minio_root_password=$$MINIO_ROOT_PASSWORD"

all: apply-infra get-kubeconfig wait-for-cluster apply-platform

clean:
	find . -name ".terraform" -type d -exec rm -rf {} + 2>/dev/null || true
	find . -name "*.tfstate" -delete 2>/dev/null || true
	find . -name "*.tfplan" -delete 2>/dev/null || true
