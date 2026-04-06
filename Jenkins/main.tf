terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

# 1. Jenkins Namespace
resource "kubernetes_namespace_v1" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

# 2. Credentials Secret
resource "kubernetes_secret_v1" "jenkins_credentials" {
  metadata {
    name      = "jenkins-credentials"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  data = {
    "admin-password"       = var.jenkins_admin_password
    "aliyun-registry-user" = var.aliyun_registry_user
    "aliyun-registry-pass" = var.aliyun_registry_pass
    "github-user"          = var.github_user
    "github-token"         = var.github_token
  }
}

# 3. Jenkins Helm Release
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  namespace  = kubernetes_namespace_v1.jenkins.metadata[0].name
  create_namespace = false

  depends_on = [kubernetes_secret_v1.jenkins_credentials]

  values = [
    templatefile("values.yaml", {
      JENKINSFILE_CONTENT = " ${indent(22, file("../Jenkins-pipeline/Jenkinsfile"))}"
    })
  ]
}

# ====================== 更安全的 RBAC 配置 ======================

# 自定义 Role：只给 jenkins namespace 内的必要权限
resource "kubernetes_role_v1" "jenkins_ci_role" {
  metadata {
    name      = "jenkins-ci-role"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "pods/exec", "services", "configmaps", "secrets", "endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "deployments/scale", "statefulsets", "daemonsets", "replicasets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

# RoleBinding：把上面 Role 绑定给 Jenkins 的 ServiceAccount
resource "kubernetes_role_binding_v1" "jenkins_ci_binding" {
  metadata {
    name      = "jenkins-ci-binding"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.jenkins_ci_role.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "jenkins"                                   # Jenkins Helm Chart 默认的 ServiceAccount
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  depends_on = [helm_release.jenkins]   # 确保 ServiceAccount 已创建
}

# ================================================================

output "jenkins_url" {
  value = "Check your K8s LoadBalancer for external IP"
}