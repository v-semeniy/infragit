resource "aws_iam_openid_connect_provider" "gitlab" {
  url             = "https://gitlab.com"
  client_id_list  = ["https://gitlab.com"]
  #thumbprint_list = ["a031c46782e6e6c662c2c87c76da9aa62ccabd8e"] # оновлений fingerprint GitLab
}

resource "aws_iam_role" "gitlab_oidc_role" {
  name = "GitLabOIDCRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.gitlab.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "gitlab.com:sub" = "project_path:vsemeniy/first_ci_cd:ref_type:branch:ref:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_admin_policy" {
  role       = aws_iam_role.gitlab_oidc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
