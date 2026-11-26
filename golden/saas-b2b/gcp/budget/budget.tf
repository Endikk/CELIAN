# The budget alert of the demo (ENF-05; ADR-008, question 1, decided by the DSI
# on 2026-11-25). It sits in its own root because a budget belongs to the
# billing account: it takes roles/billing.costsManager there, which the
# identity of gcp/tofu/ must never hold. Attributes: research RS-26.
#
# An alert caps nothing: the page of Google says that a budget "doesn't
# automatically set a hard cap on spending" (R-05). Costs reach Cloud Billing
# with a delay, and the first alert can take several hours.

# The Billing Budgets API is enabled on the project that makes the calls, and
# kept at destroy, like the APIs of gcp/tofu/.
resource "google_project_service" "billingbudgets" {
  project            = var.project_id
  service            = "billingbudgets.googleapis.com"
  disable_on_destroy = false
}

resource "google_billing_budget" "demo" {
  billing_account = var.billing_account_id
  display_name    = "${var.name}-budget"

  budget_filter {
    # Only this project: a budget without the filter counts the whole billing
    # account. The filter takes the project number.
    projects = ["projects/${var.project_number}"]

    # The month, which starts at 12 AM Pacific Time. FORECASTED_SPEND below
    # needs a calendar period, not a custom one.
    calendar_period = "MONTH"

    # Gross cost: with the default, INCLUDE_ALL_CREDITS, a free trial or a
    # promotion hides the spend and no alert fires.
    credit_types_treatment = "EXCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.budget_currency
      units         = tostring(var.budget_amount)
    }
  }

  # Thresholds on the actual spend: 50, 90 and 100 % are the defaults of the
  # console. The fourth warns before the money is spent: the month is on
  # course to reach the amount.
  threshold_rules {
    threshold_percent = 0.5
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  # No all_updates_rule: the alerts go to the default recipients, the
  # Billing Account Administrators and Users of the account. S15 refuses
  # disable_default_iam_recipients = true.

  depends_on = [google_project_service.billingbudgets]
}
