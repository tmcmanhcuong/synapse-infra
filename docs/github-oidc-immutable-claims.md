# GitHub Actions OIDC — Immutable Subject Claims

## Background

GitHub Actions hỗ trợ OIDC (OpenID Connect) để workflows có thể assume IAM roles trên AWS mà không cần lưu static credentials (Access Key / Secret Key) trong secrets.

Flow: GitHub Actions → request OIDC token → gửi token tới AWS STS → STS validate token → cấp temporary credentials.

## Thay đổi: Immutable Subject Claims (2026)

### Trước đây (mutable format)

```
repo:<owner>/<repo>:<context>
```

Ví dụ:
```
repo:tmcmanhcuong/synapse-infra:pull_request
repo:tmcmanhcuong/synapse-infra:ref:refs/heads/main
```

### Bây giờ (immutable format)

```
repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
```

Ví dụ:
```
repo:tmcmanhcuong@101078914/synapse-infra@1336067660:pull_request
repo:tmcmanhcuong@101078914/synapse-infra@1336067660:ref:refs/heads/main
```

### Timeline

- **April 2026**: GitHub announce immutable subject claims
- **July 15, 2026**: Repos tạo SAU ngày này tự động dùng immutable format
- Repos tạo TRƯỚC có thể opt-in hoặc giữ format cũ

### Tại sao thay đổi?

Format cũ dùng **tên** (username + repo name) → có thể bị exploit:

1. **Rename attack**: User rename repo → tên cũ available → kẻ tấn công tạo repo cùng tên → assume role
2. **Transfer attack**: Repo transfer sang org khác → tên cũ available
3. **Delete + recreate**: Xoá repo rồi tạo lại cùng tên dưới account khác

Immutable format dùng **numeric ID**:
- `owner_id` (101078914) — ID cố định của GitHub user/org
- `repo_id` (1336067660) — ID cố định của repository

ID không bao giờ tái sử dụng → rename/transfer/delete không ảnh hưởng trust policy.

## Cách lấy Owner ID và Repo ID

### Qua API

```bash
# Owner ID
curl -s https://api.github.com/users/tmcmanhcuong | jq '.id'
# → 101078914

# Repo ID
curl -s https://api.github.com/repos/tmcmanhcuong/synapse-infra | jq '.id'
# → 1336067660
```

### Qua GitHub CLI

```bash
gh api repos/tmcmanhcuong/synapse-infra --jq '{owner_id: .owner.id, repo_id: .id}'
```

### Qua OIDC token debug (trong workflow)

```yaml
- name: Debug OIDC token
  run: |
    TOKEN=$(curl -sS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
      "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=sts.amazonaws.com" | jq -r '.value')
    echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | jq '{sub, aud, iss}'
```

## Cách kiểm tra repo dùng format nào

```bash
gh api repos/<owner>/<repo>/actions/oidc/customization/sub
```

Output:
```json
{
  "use_default": true,
  "use_immutable_subject": false,
  "sub_claim_prefix": "repo:tmcmanhcuong@101078914/synapse-infra@1336067660"
}
```

Nếu có `sub_claim_prefix` chứa `@<id>` → repo dùng immutable format.

## AWS Trust Policy

### Trust policy cho immutable format

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<owner>@<owner_id>/<repo>@<repo_id>:ref:refs/heads/main",
            "repo:<owner>@<owner_id>/<repo>@<repo_id>:pull_request"
          ]
        }
      }
    }
  ]
}
```

### Synapse-infra specific

```json
"StringLike": {
  "token.actions.githubusercontent.com:sub": [
    "repo:tmcmanhcuong@101078914/synapse-infra@1336067660:ref:refs/heads/main",
    "repo:tmcmanhcuong@101078914/synapse-infra@1336067660:pull_request"
  ]
}
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Trust policy sub không match actual OIDC token | Debug token → update trust policy |
| Token sub có `@<id>` nhưng policy không có | Repo dùng immutable format, policy dùng format cũ | Thêm ID vào policy |
| Format cũ hoạt động trước nhưng giờ fail | GitHub migrate repo sang immutable | Update trust policy |

## References

- [GitHub Docs — OIDC Reference](https://docs.github.com/en/actions/reference/security/oidc)
- [GitHub Blog — Immutable Subject Claims (Aug 2026)](https://www.linuxtek.ca/2026/08/04/github-actions-oidc-changes/)
- [Microsoft — Migrate to Immutable Subjects](https://learn.microsoft.com/en-us/entra/workload-id/workload-identities-github-immutable-subjects)
