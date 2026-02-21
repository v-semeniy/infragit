{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::412381736597:oidc-provider/gitlab.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringLike": {
                    "gitlab.com:sub": [
                        "project_path:vsemeniy/first_ci_cd:ref_type:branch:ref:*"
                    ]
                }
            }
        }
    ]
}