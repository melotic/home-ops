terraform {
  required_version = ">= 1.5.0"

  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 4.0"
    }
  }
}

provider "grafana" {
  url  = var.stack_url
  auth = var.token

  # The provider derives the OnCall host from the stack's IRM plugin settings and
  # lands on us-central-0, which is not this stack's region. Pin it instead.
  oncall_url = "https://oncall-prod-us-east-0.grafana.net/oncall"
}

# Paging path for homelab alerts: Alertmanager posts to the zion integration,
# its default route hands the alert to the homelab chain, and the chain's only
# step notifies Justin. Without a route wired to a chain, IRM ingests alerts and
# pages nobody.

data "grafana_oncall_user" "justin" {
  username = "melotic"
}

resource "grafana_oncall_escalation_chain" "homelab" {
  name = "homelab"
}

resource "grafana_oncall_escalation" "notify_justin" {
  escalation_chain_id = grafana_oncall_escalation_chain.homelab.id
  type                = "notify_persons"
  persons_to_notify   = [data.grafana_oncall_user.justin.id]
  position            = 0
}

resource "grafana_oncall_integration" "zion" {
  name = "zion"
  type = "alertmanager"

  default_route {
    escalation_chain_id = grafana_oncall_escalation_chain.homelab.id
  }

  # Hand-tuned alert body, adopted verbatim so the import does not blank it.
  templates {
    mobile_app {}
    web {
      title   = "[{{ payload.status | default('firing') | upper }}] {{ payload.commonLabels.alertname | default('Alert') }}"
      message = <<TEMPLATE
{% set severity = payload.commonLabels.severity | default('unknown') -%}
**{{ payload.commonLabels.alertname | default('Alert') }}**
{%- if severity == 'critical' %} 🔴 CRITICAL
{%- elif severity == 'warning' %} 🟠 WARNING
{%- else %} ℹ️ INFO{% endif %}

**Details:**
{%- for alert in payload.alerts %}

{%- set joined = [] %}
{%- for name, key in [("Cluster", "cluster"), ("Namespace", "namespace"), ("Instance", "instance"), ("Pod", "pod")] %}
{%- if key in alert.labels %}{% set _ = joined.append("- " ~ name ~ ": " ~ alert.labels[key]) %}{% endif %}
{%- endfor %}
{%- set _ = joined.append("- Summary: " ~ (alert.annotations.summary | default('N/A'))) %}
{%- if alert.annotations.description %}{% set _ = joined.append("- Description: " ~ alert.annotations.description) %}{% endif %}
{{ joined | join("\n") }}
{%- endfor %}

{%- set runbook = payload.commonAnnotations.runbook_url | default(payload.commonAnnotations.documentation, true) | default('') %}
{%- if runbook %}

**Runbook:** {{ runbook }}
{%- endif %}

**Alertmanager:** {{ payload.externalURL | default('N/A') }}
TEMPLATE
    }
  }
}

# These three objects already exist in IRM (created through the API before this
# stack was managed). Import keeps the first apply a no-op instead of creating a
# second integration with a new webhook URL that Alertmanager would not be using.
import {
  to = grafana_oncall_escalation_chain.homelab
  id = "F1964ULXQEMLJ"
}

import {
  to = grafana_oncall_escalation.notify_justin
  id = "ETQNUR24ZHZXU"
}

import {
  to = grafana_oncall_integration.zion
  id = "C7EP612XU3A6D"
}

output "integration_url" {
  value     = grafana_oncall_integration.zion.link
  sensitive = true
}
