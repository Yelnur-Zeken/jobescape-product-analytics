# Data Dictionary

Canonical metric and entity definitions used in this internship work.
These should be the single source of truth — if a stakeholder uses a
different definition, refer them here first.

## Source tables

| Table | Description | Partition |
|---|---|---|
| `` `events.funnel-raw-table` `` | Pre-signup quiz / acquisition events with prefix `pr_funnel_*` | `DATE(timestamp)` |
| `` `events.app-raw-table` `` | Post-signup webapp events with prefix `pr_webapp_*` | `DATE(timestamp)` |
| `` `payments.all_payments_prod` `` | Unified Adyen + Airwallex payments. `amount` in cents, `created_at` in microseconds | — |
| `` `analytics_draft.intercom_tickets` `` | Intercom conversations enriched with tags | — |
| `ab_tests.ab_tests` | Long-format experiment metric values | — |

Both `events.*` tables share the same column model: `event_id`, `user_id`,
`device_id`, `event_name`, `timestamp`, `country_code`, `ip`,
`user_agent`, `referrer`, `attribution_id`, plus three JSON columns
`event_metadata`, `query_parameters`, `user_metadata`.

## User-level entities

| Field | Source | Notes |
|---|---|---|
| `user_id` | `events.*-raw-table.user_id` | Primary user identifier. Stable across sessions and devices once authenticated. |
| `device_id` | `events.*-raw-table.device_id` | Device-level identifier. Pre-auth users are keyed on this. |
| `attribution_id` | `events.*-raw-table.attribution_id` | Joins to ad-platform attribution. |
| `purch_date` | `DATE(MIN(timestamp))` where `event_name = 'pr_funnel_subscribe'` | Cohort entry day. |

## Geo bucketing

```sql
CASE
  WHEN country_code IN ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES',
                        'FI','FR','GB','HK','IE','IL','IT','JP','KR','NL',
                        'NO','PT','QA','SA','SE','SG','SI','US','NZ') THEN 'T1'
  ELSE 'WW'
END AS geo
```

## Retention

Two parallel definitions are computed and reported separately. A user
is "retained on day N" if at least one of the events listed below fires
on `purch_date + N days`. Day N is bucketed via
`TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE)` in 1440-minute
steps up to Day 30, with a `> 30` overflow bucket.

- **Lessons-retention** — events
  `pr_webapp_lesson_started`, `pr_webapp_lesson_completed`,
  `pr_webapp_lesson_csat_click`, `pr_webapp_course_csat_click`
- **AI-Tools-retention** — events
  `pr_webapp_ai_chat_message_sent`, `pr_webapp_ai_chat_message_received`,
  `pr_webapp_ai_assistant_generate_click`,
  `pr_webapp_ai_assistant_message_received`

Cohort start is `pr_funnel_subscribe` (the moment a user starts a paid
trial), filtered for `country_code != 'KZ'` and emails not matching
`%test%`.

## Upsell flow

The upsell flow is shown immediately after
`pr_webapp_registration_signup_click` and tracked through three webapp
events:

1. `pr_webapp_upsell_view`            — offer shown
2. `pr_webapp_upsell_purchase_click`  — TTP click
3. `pr_webapp_upsell_successful_purchase` — successful purchase event

The actual cash settlement is recorded in `payments.all_payments_prod`
with:

```
payment_type = 'upsell'
status       = 'settled'
rebill_count IN (-14, -20, -22)
```

where `rebill_count = -14` corresponds to `upsell_order = '1'` and
`rebill_count IN (-20, -22)` corresponds to `upsell_order = '2'`.

### Upsell metrics

- **Upsell View Count** — count of `pr_webapp_upsell_view` events on the
  cohort.
- **Upsell TTP Rate (on View)** — share of viewers that fired
  `pr_webapp_upsell_purchase_click`.
- **Upsell SR (on TTP)** — share of TTP-clickers that fired
  `pr_webapp_upsell_successful_purchase`.
- **Upsell Rate (on View)** — share of viewers that ultimately purchased.
- **Upsell Gain (on View)** — `SUM(upsell purch_amount) / COUNT(viewers)`.
- **AOV (on Purchasing Users)** — average `purch_amount` among users
  with at least one settled upsell payment.

## Funnel

```
pr_funnel_*_path -> pr_funnel_email_submit -> pr_funnel_subscribe
                  -> pr_webapp_registration_signup_click -> pr_webapp_upsell_view
```

The `*_path` event family identifies the user_path attribute:
`scale_path`, `escape_path`, `simplify_path`, `starter_path`. The
attribute is recovered first from `event_metadata` of the
`pr_funnel_subscribe` event and falls back to the most recent matching
`pr_funnel_*_path` event for that `device_id` (180-day window).

- **Onboarding Completion Rate** — share of users who fired
  `pr_funnel_subscribe` after at least one `pr_funnel_*_path` event.

## Churn

- **Unsub 12h Rate (on View)** — share of `pr_funnel_subscribe` users
  who fired `pr_webapp_unsubscribed` within 12 hours of subscribe.
- **Unsub 12h Rate (on Upsell Purchase)** — same, computed only on
  users who also fired `pr_webapp_upsell_successful_purchase`.

## Negative-effect signals (added in u15.4.0 vs u15.4.5)

- **Insufficient Funds modal interactions** — flags
  `has_insufficient_fund_view` / `has_insufficient_fund_click`
  derived from `pr_webapp_upsell_insufficient_fund_view` /
  `pr_webapp_upsell_insufficient_fund_click`.
- **Declined upsell with Insufficient Funds reason** — counted from
  `payments.all_payments_prod` with `status = 'declined'` and
  `decline_message LIKE 'Insufficient Funds'`.
- **Refund-tagged Intercom tickets** — joined by author email through
  `analytics_draft.intercom_tickets` filtered to
  `tag_name LIKE '%upsell refund%'`.

## A/B test methodology

For small samples (n=107..200 per group) and heavy-tailed metric
distributions (`purch_amount` in particular), significance is tested
with a **non-parametric bootstrap of the difference of means**:

- 10 000 iterations, resampling clean and test groups independently
  with replacement
- one-sided 95% confidence interval from percentiles
- p-value defined as `min(share of diffs ≤ 0, share of diffs ≥ 0)`

For sensitivity analysis (planning the next test), MDE for 80% target
power is computed numerically with `scipy.optimize.brentq` on top of
`power_binary` / `power_continuous` using a two-proportion z-test
approximation.

See [`notebooks/04_ab_test_bootstrap.ipynb`](../notebooks/04_ab_test_bootstrap.ipynb).
