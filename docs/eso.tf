## External secrets operator (ESO)
module "eks_external_secrets_operator_role" {
  source           = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version          = "5.10.0"
  create_role      = true
  role_name        = "aws-eks-external-secrets-operator-oidc-${var.env.prefix}-sa"
  provider_url     = module.eks_cluster.cluster_oidc_issuer_url
  role_policy_arns = [aws_iam_policy.eks_external_secrets_operator.arn]
  tags = merge(module.default_label.tags,
  tomap({ "project" = "test" }))
}

resource "aws_iam_policy" "eks_external_secrets_operator" {
  name        = "aws-eks-external-secrets-operator-policy-${var.env.prefix}"
  path        = "/eks/oidc/aws-eks-external-secrets-operator/"
  description = "Policies for external-secrets-operator (parameter store)"
  policy      = data.aws_iam_policy_document.aws_eks_external_secrets_operator.json
}

data "aws_iam_policy_document" "aws_eks_external_secrets_operator" {
  statement {
    sid    = "GetSSMParameter"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]

    resources = [
      "arn:aws:ssm:${var.env.ssm.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.env.ssm.prefix}/*",
    ]
  }
}

resource "kubernetes_namespace" "external-secrets-operator" {
  metadata {
    name = "external-secrets-operator"
    labels = {
      Terraform = "true"
    }
  }
}

###### New external secrets operator EOF
resource "helm_release" "external-secrets-operator" {
  name             = "external-secrets-operator"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets-operator"
  lint             = true
  create_namespace = false
  atomic           = true
  version          = "0.9.9"
  max_history      = 10

  values = [
    templatefile("external-secrets-operator/values.tpl.yaml", {
      iam_role_arn = module.eks_external_secrets_operator_role.iam_role_arn
    })
  ]
}

## Deploy first the helm release external-secrets-operator to avoid this error
## 'no matches for kind "ClusterSecretStore" in group "external-secrets.io"'
resource "kubernetes_manifest" "external_secrets_cluster_store" {
  manifest = yamldecode(<<-EOF
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: aws-parameter-store
    spec:
      provider:
        aws:
          service: ParameterStore
          region: eu-west-1
          auth:
            jwt:
              serviceAccountRef:
                namespace: external-secrets-operator
                name: eks-external-secrets-operator-oidc-sa
    EOF
  )
  depends_on = [helm_release.external-secrets-operator]
}