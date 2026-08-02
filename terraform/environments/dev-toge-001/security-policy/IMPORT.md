# waf-policy インポート手順

既存の Cloud Armor セキュリティポリシー `waf-policy`（プロジェクト `dev-toge-001`）を
Terraform 管理下に取り込むための手順書。

- 作業ディレクトリ: `terraform/environments/dev-toge-001/security-policy`
- 対象リソースタイプ: `google_compute_security_policy`
- 対象リソース: `projects/dev-toge-001/global/securityPolicies/waf-policy`
- Terraform: `1.15.8` / google provider: `7.42.0`（`version.tf` で固定）

`import` ブロック + `terraform plan -generate-config-out` を使い、
HCL を手書きせずに現状の設定を生成してから取り込む方針。

---

## 0. 前提条件

以下を満たしていること。

```bash
# 認証（ADC）。未設定なら実行する
gcloud auth application-default login
gcloud config set project dev-toge-001

# バージョン確認
terraform version   # 1.15.8
gcloud version
```

必要な IAM 権限（最低限）:

- `roles/compute.securityAdmin`（または `compute.securityPolicies.get` / `.list`）
- ステートバケット `gs://tf-remote-state-backend-gcs` への `roles/storage.objectAdmin`

---

## 1. インポート対象の現状を確認する

インポート前に実物の設定を控えておく。後で `terraform plan` の差分ゼロを確認する際の答え合わせに使う。

```bash
gcloud compute security-policies list --project=dev-toge-001

gcloud compute security-policies describe waf-policy \
  --project=dev-toge-001 --format=yaml > /tmp/waf-policy.before.yaml
```

現状（2026-08-02 時点）の概要:

| priority | action | description | 備考 |
| --- | --- | --- | --- |
| 100 | `allow` | ip | `srcIpRanges = ["61.203.20.83"]` |
| 1000 | `deny(403)` | xss | `evaluatePreconfiguredWaf('xss-v33-stable', ...)` + `preconfigured_waf_config` の除外設定あり |
| 2000 | `deny(403)` | sqli | `evaluatePreconfiguredWaf('sqli-v33-stable', ...)` / `preview = true` |
| 2147483647 | `allow` | Default rule | デフォルトルール。削除不可・必ず HCL に含める |

その他:

- `advanced_options_config`: `json_parsing = STANDARD` / `log_level = VERBOSE` / `request_body_inspection_size = 8KB`
- `adaptive_protection_config.layer7_ddos_defense_config.enable = false`
- `type = CLOUD_ARMOR`（グローバル。リージョナルポリシーではない）

---

## 2. `import` ブロックを記述する

`import.tf` に以下を記述する。

```hcl
import {
  to = google_compute_security_policy.waf_policy
  id = "projects/dev-toge-001/global/securityPolicies/waf-policy"
}
```

> ID は `projects/{project}/global/securityPolicies/{name}` 形式を使う。
> `{project}/{name}` や `{name}` だけでも受け付けられるが、
> 曖昧さを避けるためフル形式を推奨。

---

## 3. 初期化

```bash
cd terraform/environments/dev-toge-001/security-policy
terraform init
```

GCS バックエンド（`bucket = tf-remote-state-backend-gcs` / `prefix = dev-toge-001`）が
初期化されることを確認する。

---

## 4. 設定を自動生成する

`main.tf` が空の状態で、`-generate-config-out` を付けて `plan` を実行する。

```bash
terraform plan -generate-config-out=generated.tf
```

- `generated.tf` に `resource "google_compute_security_policy" "waf_policy" { ... }` が出力される
- この時点では `1 to import` と表示され、リソースの作成・変更は発生しない
- 出力先ファイルが既に存在するとエラーになるので、やり直す場合は先に削除する

---

## 5. 生成された設定を整える

`generated.tf` の中身を `main.tf` へ移し、以下を手直しする。

```bash
# 中身を確認してから移動する
terraform fmt generated.tf
```

手直しのポイント:

1. **読み取り専用属性を削除する**
   `fingerprint` / `self_link` / `policy_id` / `creation_timestamp` などが出力されていたら消す。
   （provider が付けてくる場合があるが、設定として書く必要はない）
2. **空ブロックを削除する**
   `preconfigured_waf_config {}` のような空のブロックは削除してよい（API 応答の `{}` 由来）。
   ただし priority 1000 のルールが持つ `exclusions` は**実設定なので残す**。
3. **デフォルトルール（priority 2147483647）は必ず残す**
   `google_compute_security_policy` は `rule` をインライン管理する。
   デフォルトルールを HCL から消すと、apply 時に削除しようとして失敗する。
4. **`preview = true`（priority 2000 の sqli ルール）を落とさない**
   落とすと本番で `deny(403)` が有効化されてしまう。
5. `project` 引数を明示しておくと、provider 設定に依存せず読みやすい。

整え終わったら不要ファイルを消す。

```bash
rm generated.tf
terraform fmt
```

---

## 6. 差分ゼロを確認する

```bash
terraform plan
```

期待する出力:

```
Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
```

`0 to change, 0 to destroy` **以外**が出た場合は apply してはいけない。
`main.tf` の記述が実物とずれているので、`/tmp/waf-policy.before.yaml` と突き合わせて修正する。

よくあるずれ:

- `expression` の文字列（クォートやスペース）が実物と一致していない
- `advanced_options_config` を書き忘れている → デフォルト値に戻す差分が出る
- `preconfigured_waf_config` の `exclusions` の記述漏れ

---

## 7. インポートを実行する

```bash
terraform apply
```

`Apply complete! Resources: 1 imported, 0 added, 0 changed, 0 destroyed.` を確認する。

---

## 8. 事後確認

```bash
# ステートに載ったか
terraform state list
terraform state show google_compute_security_policy.waf_policy

# 再度 plan して No changes になること
terraform plan

# 実リソースが変わっていないこと
gcloud compute security-policies describe waf-policy \
  --project=dev-toge-001 --format=yaml > /tmp/waf-policy.after.yaml
diff /tmp/waf-policy.before.yaml /tmp/waf-policy.after.yaml
```

`diff` は `fingerprint` 以外に差分が出ないこと（`fingerprint` は更新のたびに変わる値）。

---

## 9. 後片付け

インポート完了後、`import.tf` の `import` ブロックは残しておいても害はないが、
役目を終えているので削除して構わない（削除しても再インポートは発生しない）。

```bash
# import.tf を空にする、またはファイルごと削除
rm import.tf
terraform plan   # No changes を確認
```

コミットして PR を作成する。

---

## 参考: ロールバック（ステートから外す）

実リソースには一切触れずに Terraform 管理から外す場合。

```bash
terraform state rm google_compute_security_policy.waf_policy
```

`terraform destroy` は実リソースを削除するので、切り戻し目的では絶対に使わない。

---

## 参考: import ブロックを使わない従来方式

```bash
# main.tf に resource ブロックを手書きしてから
terraform import google_compute_security_policy.waf_policy \
  projects/dev-toge-001/global/securityPolicies/waf-policy
```

HCL を全て手書きする必要があり、差分確認が apply 後になるため、
本手順では `import` ブロック方式を採用している。
