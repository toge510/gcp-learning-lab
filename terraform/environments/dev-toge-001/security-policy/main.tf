resource "google_compute_security_policy" "waf_policy" {
  project     = "dev-toge-001"
  name        = "waf-policy"
  description = "waf policy"
  type        = "CLOUD_ARMOR"

  adaptive_protection_config {
    layer_7_ddos_defense_config {
      enable = false
    }
  }

  advanced_options_config {
    json_parsing                 = "STANDARD"
    log_level                    = "VERBOSE"
    request_body_inspection_size = "8KB"
  }

  rule {
    priority    = 100
    action      = "allow"
    description = "ip"
    preview     = false

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["61.203.20.83"]
      }
    }
  }

  rule {
    priority    = 1000
    action      = "deny(403)"
    description = "xss"
    preview     = false

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('xss-v33-stable', {'sensitivity': 2, 'opt_out_rule_ids': ['owasp-crs-v030301-id941100-xss', 'owasp-crs-v030301-id941101-xss']})"
      }
    }

    preconfigured_waf_config {
      exclusion {
        target_rule_set = "java-v33-stable"

        request_cookie {
          operator = "EQUALS"
          value    = "session_id"
        }
      }
    }
  }

  rule {
    priority    = 2000
    action      = "deny(403)"
    description = "sqli"
    preview     = true

    match {
      expr {
        expression = "evaluatePreconfiguredWaf('sqli-v33-stable', {'sensitivity': 1, 'opt_out_rule_ids': ['owasp-crs-v030301-id942100-sqli', 'owasp-crs-v030301-id942101-sqli']})"
      }
    }
  }

  # デフォルトルール。削除できないため必ず記述する
  rule {
    priority    = 2147483647
    action      = "allow"
    description = "Default rule, higher priority overrides it"
    preview     = false

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}
