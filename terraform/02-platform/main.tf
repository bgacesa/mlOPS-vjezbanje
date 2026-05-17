# =============================================================================
# ECR — Container Registry
# =============================================================================
resource "aws_ecr_repository" "mlops" {
  name                 = "${var.project_name}/${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "mlops" {
  repository = aws_ecr_repository.mlops.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Zadrži zadnjih 20 image-a"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

# =============================================================================
# Namespaces
# =============================================================================
locals {
  namespaces = [
    "monitoring",
    "mlflow",
    "argo",
    "kserve",
    "minio",
    "kubeflow",
    "argocd",
    "cert-manager",
    "feast",
  ]
}

resource "kubernetes_namespace" "platform" {
  for_each = toset(local.namespaces)

  metadata {
    name = each.key
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "project"                      = var.project_name
    }
  }
}

# =============================================================================
# cert-manager — TLS certifikati (dependency za KServe)
# =============================================================================
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.14.5"
  namespace  = "cert-manager"

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [kubernetes_namespace.platform]
  timeout    = 300
}

# =============================================================================
# Prometheus + Grafana (kube-prometheus-stack)
# =============================================================================
resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "58.4.0"
  namespace  = "monitoring"

  values = [file("${path.module}/helm-values/kube-prometheus-stack.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }

  depends_on = [kubernetes_namespace.platform]
  timeout    = 600

  lifecycle {
    ignore_changes = [version]
  }
}

# =============================================================================
# MinIO — S3-kompatibilni artifact storage
# =============================================================================
resource "helm_release" "minio" {
  name       = "minio"
  repository = "https://charts.min.io/"
  chart      = "minio"
  version    = "5.2.0"
  namespace  = "minio"

  values = [file("${path.module}/helm-values/minio.yaml")]

  set_sensitive {
    name  = "rootUser"
    value = var.minio_root_user
  }

  set_sensitive {
    name  = "rootPassword"
    value = var.minio_root_password
  }

  depends_on = [kubernetes_namespace.platform]
  timeout    = 300
}

# =============================================================================
# MLflow — Experiment tracking
# =============================================================================
resource "helm_release" "mlflow" {
  name       = "mlflow"
  repository = "https://community-charts.github.io/helm-charts"
  chart      = "mlflow"
  version    = "0.7.19"
  namespace  = "mlflow"

  values = [file("${path.module}/helm-values/mlflow.yaml")]

  set_sensitive {
    name  = "extraEnvVars[0].value"
    value = var.minio_root_user
  }

  set_sensitive {
    name  = "extraEnvVars[1].value"
    value = var.minio_root_password
  }

  depends_on = [
    kubernetes_namespace.platform,
    helm_release.minio,
  ]
  timeout = 300
}

# =============================================================================
# Argo Workflows — DAG-based ML pipeline engine
# =============================================================================
resource "helm_release" "argo_workflows" {
  name       = "argo-workflows"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-workflows"
  version    = "0.41.7"
  namespace  = "argo"

  values = [file("${path.module}/helm-values/argo-workflows.yaml")]

  depends_on = [kubernetes_namespace.platform]
  timeout    = 300
}

# =============================================================================
# ArgoCD — GitOps continuous deployment
# =============================================================================
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_version
  namespace  = "argocd"

  values = [file("${path.module}/helm-values/argocd.yaml")]

  depends_on = [kubernetes_namespace.platform]
  timeout    = 600
}

# =============================================================================
# KServe — Model serving (zahtijeva cert-manager)
# =============================================================================
resource "helm_release" "kserve_crd" {
  name       = "kserve-crd"
  repository = "https://kserve.github.io/helm-charts"
  chart      = "kserve-crd"
  version    = "v0.13.0"
  namespace  = "kserve"

  depends_on = [
    kubernetes_namespace.platform,
    helm_release.cert_manager,
  ]
  timeout = 300
}

resource "helm_release" "kserve" {
  name       = "kserve"
  repository = "https://kserve.github.io/helm-charts"
  chart      = "kserve"
  version    = "v0.13.0"
  namespace  = "kserve"

  values = [file("${path.module}/helm-values/kserve.yaml")]

  depends_on = [
    helm_release.kserve_crd,
    helm_release.cert_manager,
  ]
  timeout = 600
}

# =============================================================================
# Kubeflow — Kubeflow nema oficijalni Helm chart.
# Deployamo ga kroz ArgoCD Application koji koristi kustomize manifeste
# iz oficijalne kubeflow/manifests GitHub repo.
#
# Koristimo null_resource + local-exec umjesto kubernetes_manifest jer
# kubernetes_manifest validira CRD tokom plan faze — a ArgoCD CRD-ovi
# ne postoje dok ArgoCD nije instaliran (chicken-and-egg problem).
# =============================================================================
resource "null_resource" "kubeflow_argocd_app" {
  triggers = {
    kubeflow_version = var.kubeflow_version
    argocd_release   = helm_release.argocd.metadata[0].revision
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Čekam da ArgoCD CRD-ovi budu registrirani..."
      until kubectl --kubeconfig=${var.kubeconfig_path} \
        get crd applications.argoproj.io &>/dev/null; do
        sleep 5
      done
      echo "ArgoCD CRD-ovi su spremni, kreiram Kubeflow Application..."
      kubectl --kubeconfig=${var.kubeconfig_path} apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/kubeflow/manifests
    targetRevision: ${var.kubeflow_version}
    path: example
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: false
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
    EOT
  }

  depends_on = [helm_release.argocd]
}
