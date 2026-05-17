# MLOps Vjezba — Platforma na AWS EC2 + Kubernetes

Self-managed MLOps platforma deployovana na single-node Kubernetes (kubeadm) na AWS EC2.

## Arhitektura

| Sloj | Komponenta | Namjena | Provisioning |
|------|-----------|---------|-------------|
| Infrastruktura | AWS EC2 (t3.2xlarge) | Kompjutski resursi | `terraform/01-infra` |
| Mreža | VPC, Subnet, SG, IGW | Mrežna izolacija | `terraform/01-infra/modules/network` |
| Orchestracija | Kubernetes 1.29 (kubeadm) | Container management | EC2 user_data skripte |
| ML Platforma | Kubeflow | ML workflow orkestrator | ArgoCD → kustomize |
| Experiment Tracking | MLflow | Praćenje eksperimenata | `helm_release` |
| Pipeline Engine | Argo Workflows | DAG-based ML pipeline | `helm_release` |
| Model Serving | KServe | Real-time serving | `helm_release` |
| Feature Store | Feast | Upravljanje feature-ima | GitHub Actions job |
| Artifact Storage | MinIO | S3-kompatibilni storage | `helm_release` |
| Monitoring | Prometheus + Grafana | Metrike i dashboardi | `helm_release` |
| CI/CD | GitHub Actions | Workflow automatizacija | `.github/workflows/` |
| GitOps CD | ArgoCD | Kontinuirani deployment | `helm_release` |
| Container Registry | GHCR + ECR | Docker image hosting | GitHub Actions + Terraform |

## Struktura projekta

```
.
├── terraform/
│   ├── 01-infra/              # Faza 1: VPC + EC2 + kubeadm bootstrap
│   │   └── modules/
│   │       ├── network/       # VPC, Subnet, IGW, Security Group
│   │       └── compute/       # EC2, EBS, EIP, IAM, kubeadm init script
│   └── 02-platform/           # Faza 2: Helm releases na Kubernetes
│       └── helm-values/       # Values fajlovi za svaki Helm chart
└── .github/
    └── workflows/
        ├── 01-infra.yml       # Terraform za infrastrukturu
        ├── 02-platform.yml    # Terraform za ML platformu
        ├── feast-deploy.yml   # Feast feature store deploy
        └── build-push.yml     # Docker build → GHCR + ECR
```

## Preduvjeti

- AWS account sa pravima za EC2, VPC, IAM, ECR
- AWS CLI konfigurisan (`aws configure`)
- Terraform >= 1.6.0
- kubectl
- Helm >= 3.x
- GitHub CLI (`gh`)
- SSH key par kreiran u AWS regionu

## Quickstart

### 1. Kloniraj i konfiguriši

```bash
git clone https://github.com/bgacesa/mlOPS-vjezbanje
cd mlOPS-vjezbanje

cp terraform/01-infra/terraform.tfvars.example terraform/01-infra/terraform.tfvars
# Uredi terraform.tfvars — postavi key_name i ostale varijable

cp terraform/02-platform/terraform.tfvars.example terraform/02-platform/terraform.tfvars
# Uredi terraform.tfvars — postavi lozinke
```

### 2. Deploy infrastrukture

```bash
make init-infra
make plan-infra KEY_NAME=tvoj-key-name
make apply-infra KEY_NAME=tvoj-key-name
```

### 3. Preuzmi kubeconfig (čekaj ~5 min za bootstrap)

```bash
make get-kubeconfig KEY_NAME=tvoj-key-name
export KUBECONFIG=~/.kube/mlops-config
kubectl get nodes  # mora biti Ready
```

### 4. Deploy ML platforme

```bash
export MINIO_ROOT_PASSWORD="tvoja-lozinka"
make init-platform
make apply-platform
```

### 5. Provjeri servise

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}')

# MLflow
echo "MLflow: http://$NODE_IP:30500"

# Grafana (admin / iz terraform.tfvars)
echo "Grafana: http://$NODE_IP:30300"

# MinIO Console
echo "MinIO: http://$NODE_IP:30901"

# ArgoCD
echo "ArgoCD: http://$NODE_IP:30080"
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Argo Workflows
echo "Argo Workflows: http://$NODE_IP:30274"
```

## GitHub Actions Secrets

Postavi u GitHub repozitoriju (Settings → Secrets):

| Secret | Opis |
|--------|------|
| `AWS_ROLE_ARN` | ARN IAM role za OIDC autentifikaciju |
| `EC2_KEY_NAME` | Naziv SSH key para u AWS |
| `MINIO_ROOT_PASSWORD` | MinIO root lozinka |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin lozinka |

GitHub Variables:

| Variable | Opis |
|----------|------|
| `AWS_REGION` | AWS region (default: eu-central-1) |
| `K8S_MASTER_IP` | Public IP mastera (automatski postavlja 01-infra workflow) |

## AWS IAM OIDC Setup za GitHub Actions

```bash
# Kreiraj OIDC provider za GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Kreiraj trust policy i IAM rolu
# (detalji u terraform/iam-github-oidc/ — opciono)
```

## Troškovi (procjena za dev)

| Resurs | Tip | Cijena/h |
|--------|-----|---------|
| EC2 | t3.2xlarge | ~$0.33 |
| EBS root | 50GB gp3 | ~$0.004 |
| EBS data | 100GB gp3 | ~$0.008 |
| EIP | Static IP | ~$0.005 |
| **Ukupno** | | **~$0.35/h (~$250/mj)** |

> **Savjet**: Stopaj instancu kada je ne koristiš — `aws ec2 stop-instances --instance-ids <id>`

## Poznate napomene

- **Kubeflow**: Nema oficijalni Helm chart. Deployava se via ArgoCD → kubeflow/manifests (kustomize). Inicijalni sync može trajati 10-20 min.
- **Single-node**: Control-plane taint je uklonjen — podovi se scheduliraju na master node.
- **TLS**: KServe zahtijeva cert-manager. Konfiguriši pravi domain i Ingress za produkciju.
- **Feast**: Koristi MinIO kao offline store i registry. Redis za online store nije deployovan — dodati `bitnami/redis` Helm release ako je potreban.
