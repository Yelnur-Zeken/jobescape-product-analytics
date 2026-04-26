# Data Dictionary

Canonical metric definitions used in this internship work. These should be the single source of truth — if a stakeholder uses a different definition, refer them here first.

## User-level entities

| Field | Source | Notes |
|---|---|---|
| `user_id` | `events.app_raw_table.user_id` | Primary user identifier. Stable across sessions and devices once authenticated. |
| `device_id` | `events.app_raw_table.device_id` | Device-level identifier. Pre-auth users are keyed on this. |
| `attribution_id` | `events.app_raw_table.attribution_id` | Joins to ad-platform attribution. |
| `install_date` | `MIN(timestamp)` where `event_name = 'app_install'` | One row per `user_id`. |

## Activity definitions

- **Active user (DAU/WAU/MAU)** — distinct `user_id` with at least one event of any name in the window.
- **Session** — series of events from the same `user_id` separated by less than 30 minutes of inactivity.

## Retention

- **Retention D_n** — share of cohort users with at least one event on `install_date + n days`. Cohorts are bucketed by `install_date`. We track D1, D3, D5, D7.

## Onboarding funnel

The canonical step order:

```
app_open -> onboarding_start -> goal_selected -> level_selected -> personalization_done -> paywall_view -> trial_start
```

- **Onboarding Completion Rate** — share of `app_open` users that reach `personalization_done` within 24 hours.

## Engagement

- **AI Chat / Workflow Start Rate (D0..D7)** — share of cohort users who fired any of `ai_chat_start`, `ai_assistant_start`, `ai_workflow_start` within the given window since install.
- **First Lesson Completion Rate (all time)** — share of users who fired `lesson_complete` at least once.
- **3 Lessons Completion Rate** — share of users who fired `lesson_complete` at least three times.
- **Median Learning Session Time** — `APPROX_QUANTILES(session_minutes, 100)[50]` over learning sessions.

## Monetization

- **Trial start** — `event_name = 'trial_start'` in events table.
- **First purchase / Upsell / Renewal** — categorized by `payment_type` in the `payments` table.
- **Upsell Gain** — `sum(upsell revenue) / sum(first_purchase revenue)`.
- **ARPU 90d** — `sum(payment amount within 90 days of install) / paying_users`.

## Churn

- **Unsub Rate 12h / 24h** — share of users who fired `subscription_cancel` within 12 / 24 hours of `trial_start` or `subscription_start`.

## Reviews and feedback

- **CSAT score / weight** — sourced from in-app survey events (`event_name = 'csat_submitted'`, `JSON_VALUE(event_metadata, '$.score')`).
- **iOS App Store review / Trustpilot review** — pulled from external review APIs (not from BigQuery).
