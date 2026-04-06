terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
    }
    helm = {
      source  = "hashicorp/helm"
    }
  }
}

# 1. Kubernetes Provider for Helm (Local Docker Desktop)
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

# 2. Jenkins Namespace (must exist before Secret and Helm release)
resource "kubernetes_namespace_v1" "jenkins" {
  metadata {
    name = "jenkins"
  }
}

# 3. Credentials Secret (referenced by Jenkins via extraEnv)
resource "kubernetes_secret_v1" "jenkins_credentials" {
  metadata {
    name      = "jenkins-credentials"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  data = {
    "admin-password"      = var.jenkins_admin_password
    "aliyun-registry-user" = var.aliyun_registry_user
    "aliyun-registry-pass" = var.aliyun_registry_pass
    "github-user"          = var.github_user
    "github-token"         = var.github_token
  }

}

# 4. Jenkins Helm Release
resource "helm_release" "jenkins" {
  name       = "jenkins"
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  namespace  = kubernetes_namespace_v1.jenkins.metadata[0].name
  create_namespace = false

  depends_on = [kubernetes_secret_v1.jenkins_credentials]

  values = [
    templatefile("values.yaml", {
      JENKINSFILE_CONTENT = "                      ${indent(22, file("../Jenkins-pipeline/Jenkinsfile"))}"
    })
  ]
}


# 5. Define Jenkins role and role binding for Jenkins to access the Kubernetes API (optional, but recommended for security)
resource "kubernetes_role_v1" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["pods", "services", "deployments", "configmaps", "secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "jenkins" {
  metadata {
    name      = "jenkins"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.jenkins.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }
} 

output "jenkins_url" {
  value = "Check your K8s LoadBalancer for external IP"
}
