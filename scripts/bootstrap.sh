#!/usr/bin/env bash
# scripts/bootstrap.sh
set -euo pipefail
ansible-playbook -i ansible/inventory.ini ansible/playbooks/01-host.yml --tags "${HOST_TAGS:-gpu,tools}"   # fresh machine: HOST_TAGS=host-base,gpu,tools
ansible-playbook -i ansible/inventory.ini ansible/playbooks/02-models.yml
( cd terraform/cluster && terraform init && terraform apply -auto-approve )
( cd terraform/platform && terraform init \
  && terraform apply -auto-approve -target=helm_release.kube_prometheus_stack -target=helm_release.argocd \
  && terraform apply -auto-approve )          # second pass: CRDs now exist for PrometheusRule and Application
