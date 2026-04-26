# Looker Studio — Step-by-step build guide

Three dashboards, ~10–15 minutes each. Read access to BigQuery is enough — we use Custom Queries, no `CREATE VIEW` permission required.

## ⚠️ Cost safety BEFORE you start

Looker Studio re-runs the underlying query **every time the dashboard is loaded or a filter is changed**. Without precautions this can scan a lot of data. Rules:

1. **Always extract data after wiring up Custom Query.** In Looker Studio, after adding the Custom Query data source, click **Extract Data** (left sidebar → blue button). This caches the result and stops re-querying BigQuery on every interaction. Refresh the extract once a day, not on every page load.
2. **Use the short default windows below.** Each query is capped at 14 days max. Do not extend without re-running a dry-run check in the BigQuery Console.
3. **For the production team, prefer materialized views in `analytics_draft`** if you have permission. For this internship deliverable, Custom Query + Extract Data is fine and avoids needing write permissions.
4. **First time you paste a query, click "Custom Query" → paste → BEFORE clicking Add, look at the bottom: "This query will process N MB/GB". If > 5 GB — stop and ask the supervisor.**

## One-time setup (1 min)

1. Open https://lookerstudio.google.com (sign in with the same Google account that has BigQuery read access).
2. Top-left → **Create** → **Report**.
3. **Add data** dialog → **BigQuery** connector → if asked, click **Authorize**.
4. Pick **Custom Query** in the left sidebar.
5. **Billing project** → choose `hopeful-list-429812-f3`.
6. Paste the SQL for the dashboard you're building (see below) → **Add** → **Add to report**.
7. **Immediately enable Extract Data**: Resource menu → Manage added data sources → "Extract data" → set refresh schedule to **Daily**.

For each dashboard below: repeat steps 2–7, then arrange charts as described.

---

## Dashboard 1 — Cohort Retention (D1/D3/D5/D7)

### SQL to paste (14-day window, partition-pruned)

```sql
WITH cohorts AS (
  SELECT
    user_id,
    DATE(MIN(timestamp))                                                 AS cohort_date,
    ANY_VALUE(
      CASE
        WHEN JSON_VALUE(event_metadata, '$.country_code') IN
             ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
              'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
              'SE','SG','SI','US','NZ')
        THEN 'T1' ELSE 'WW' END
    )                                                                    AS geo,
    ANY_VALUE(
      CASE
        WHEN LOWER(user_agent) LIKE '%iphone%' OR LOWER(user_agent) LIKE '%ipad%' THEN 'iOS'
        WHEN LOWER(user_agent) LIKE '%android%'                          THEN 'Android'
        ELSE 'Other'
      END
    )                                                                    AS platform
  FROM `events.funnel-raw-table`
  WHERE event_name = 'pr_funnel_subscribe'
    AND country_code != 'KZ'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                            AND CURRENT_DATE()
    AND user_id IS NOT NULL
    AND user_id != 'undefined'
  GROUP BY user_id
),
activity AS (
  SELECT a.user_id,
         DATE_DIFF(DATE(a.timestamp), c.cohort_date, DAY) AS day_n
  FROM `events.app-raw-table` a
  JOIN cohorts c USING (user_id)
  WHERE a.event_name LIKE 'pr_webapp_%'
    AND DATE(a.timestamp) BETWEEN c.cohort_date
                              AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
)
SELECT
  c.cohort_date, c.geo, c.platform,
  COUNT(DISTINCT c.user_id) AS cohort_size,
  SAFE_DIVIDE(COUNT(DISTINCT IF(a.day_n=1,a.user_id,NULL)), COUNT(DISTINCT c.user_id)) AS retention_d1,
  SAFE_DIVIDE(COUNT(DISTINCT IF(a.day_n=3,a.user_id,NULL)), COUNT(DISTINCT c.user_id)) AS retention_d3,
  SAFE_DIVIDE(COUNT(DISTINCT IF(a.day_n=5,a.user_id,NULL)), COUNT(DISTINCT c.user_id)) AS retention_d5,
  SAFE_DIVIDE(COUNT(DISTINCT IF(a.day_n=7,a.user_id,NULL)), COUNT(DISTINCT c.user_id)) AS retention_d7
FROM cohorts c LEFT JOIN activity a USING (user_id)
GROUP BY cohort_date, geo, platform
```

### Charts

1. **Scorecard × 4** (top row): metric `retention_d1` (AVG aggregation) → label "Avg D1 retention". Repeat for D3/D5/D7.
2. **Time series** (mid): dimension `cohort_date`, metrics `retention_d1`, `retention_d3`, `retention_d7`.
3. **Pivot table** (bottom): rows `cohort_date`, metrics `cohort_size, retention_d1, retention_d3, retention_d7`, sort by `cohort_date` desc.
4. **Filter controls** (top-right): dropdown on `geo` (T1 / WW), dropdown on `platform` (iOS / Android / Other).
5. Title: **"Jobescape — Subscribe Cohort Retention (D1/D3/D5/D7)"**

---

## Dashboard 2 — Acquisition Funnel

### SQL to paste (14-day window)

```sql
WITH funnel_events AS (
  SELECT
    user_id, device_id, event_name, timestamp,
    DATE(timestamp)                                  AS event_date,
    JSON_VALUE(event_metadata, '$.funnel_version')   AS funnel_version,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.country_code') IN
           ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
            'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
            'SE','SG','SI','US','NZ')
      THEN 'T1' ELSE 'WW' END                        AS geo
  FROM `events.funnel-raw-table`
  WHERE event_name IN (
          'pr_funnel_scale_path','pr_funnel_escape_path',
          'pr_funnel_simplify_path','pr_funnel_starter_path',
          'pr_funnel_email_submit','pr_funnel_subscribe'
        )
    AND country_code != 'KZ'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                            AND CURRENT_DATE()
),
webapp_events AS (
  SELECT user_id, event_name, DATE(timestamp) AS event_date
  FROM `events.app-raw-table`
  WHERE event_name IN ('pr_webapp_registration_signup_click','pr_webapp_upsell_view')
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                            AND CURRENT_DATE()
)
SELECT
  COALESCE(f.event_date, w.event_date)                                         AS event_date,
  ANY_VALUE(f.funnel_version)                                                  AS funnel_version,
  ANY_VALUE(f.geo)                                                             AS geo,
  COUNT(DISTINCT IF(f.event_name LIKE 'pr_funnel_%_path', f.device_id, NULL))  AS s1_path,
  COUNT(DISTINCT IF(f.event_name = 'pr_funnel_email_submit', f.user_id, NULL)) AS s2_email,
  COUNT(DISTINCT IF(f.event_name = 'pr_funnel_subscribe',    f.user_id, NULL)) AS s3_subscribe,
  COUNT(DISTINCT IF(w.event_name = 'pr_webapp_registration_signup_click', w.user_id, NULL)) AS s4_signup,
  COUNT(DISTINCT IF(w.event_name = 'pr_webapp_upsell_view',  w.user_id, NULL)) AS s5_upsell_view
FROM funnel_events f
FULL OUTER JOIN webapp_events w ON f.user_id = w.user_id AND f.event_date = w.event_date
GROUP BY event_date
```

### Charts

1. **Bar chart** (vertical, totals): metrics `s1_path, s2_email, s3_subscribe, s4_signup, s5_upsell_view` (looks like a funnel).
2. **Calculated fields** (Add field):
   - `cr_path_to_email`     = `s2_email / s1_path`
   - `cr_email_to_sub`      = `s3_subscribe / s2_email`
   - `cr_sub_to_signup`     = `s4_signup / s3_subscribe`
   - `cr_signup_to_upsell`  = `s5_upsell_view / s4_signup`
   - Add as scorecards (top row).
3. **Time series**: dimension `event_date`, metrics `s1_path, s3_subscribe, s5_upsell_view`.
4. **Filters**: `geo`, `funnel_version`.
5. Title: **"Jobescape — Acquisition Funnel (last 14 days)"**

---

## Dashboard 3 — Upsell by Segment

### SQL to paste (7-day window — heaviest query, keep narrow!)

```sql
WITH upsell_payments AS (
  SELECT customer_account_id, rebill_count,
         SUM(amount)/100 AS upsell_amount_usd
  FROM `payments.all_payments_prod`
  WHERE TIMESTAMP_MICROS(created_at) >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
    AND status = 'settled'
    AND payment_type = 'upsell'
    AND rebill_count IN (-14, -20, -22)
  GROUP BY customer_account_id, rebill_count
)
SELECT
  COALESCE(
    JSON_VALUE(ups_view.event_metadata, '$.upsell_version'),
    REGEXP_EXTRACT(ups_view.referrer, r'[?&]upsell_version=([^&]+)')
  )                                                                          AS upsell_version,
  JSON_VALUE(fun.event_metadata, '$.funnel_version')                         AS funnel_version,
  CASE
    WHEN JSON_VALUE(fun.event_metadata, '$.country_code') IN
         ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
          'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
          'SE','SG','SI','US','NZ')
    THEN 'T1' ELSE 'WW' END                                                  AS geo,
  JSON_VALUE(ups_view.event_metadata, '$.upsell_order')                      AS upsell_order,
  COUNT(DISTINCT fun.user_id)                                                AS subscribers,
  COUNT(DISTINCT IF(ups_view.event_id  IS NOT NULL, fun.user_id, NULL))      AS exposed_users,
  COUNT(DISTINCT IF(ups_purch.event_id IS NOT NULL, fun.user_id, NULL))      AS paid_users,
  SUM(IFNULL(cash.upsell_amount_usd, 0))                                     AS upsell_revenue_usd
FROM `events.funnel-raw-table` fun
LEFT JOIN `events.app-raw-table` ups_view
  ON ups_view.event_name = 'pr_webapp_upsell_view'
 AND ups_view.user_id    = fun.user_id
 AND ups_view.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
 AND JSON_VALUE(ups_view.query_parameters, '$.source') = 'register'
LEFT JOIN `events.app-raw-table` ups_purch
  ON ups_purch.event_name = 'pr_webapp_upsell_successful_purchase'
 AND ups_purch.user_id    = fun.user_id
 AND ups_purch.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
 AND JSON_VALUE(ups_purch.query_parameters, '$.source') = 'register'
 AND JSON_VALUE(ups_purch.event_metadata,   '$.upsell_order') =
     JSON_VALUE(ups_view.event_metadata,    '$.upsell_order')
LEFT JOIN upsell_payments cash
  ON  cash.customer_account_id = ups_purch.user_id
  AND ((JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '1' AND cash.rebill_count = -14)
    OR (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '2' AND cash.rebill_count IN (-20, -22)))
WHERE fun.event_name = 'pr_funnel_subscribe'
  AND fun.country_code != 'KZ'
  AND fun.timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY)
  AND JSON_VALUE(fun.event_metadata, '$.card_type') NOT IN ('PREPAID')
  AND JSON_VALUE(fun.event_metadata, '$.channel') = 'primer'
GROUP BY upsell_version, funnel_version, geo, upsell_order
```

### Charts

1. **Bar chart**: dimension `upsell_version`, breakdown dimension `geo`, metric `paid_users`.
2. **Calculated fields**:
   - `cr_view_to_paid` = `paid_users / exposed_users`
   - `arpu_paid`       = `upsell_revenue_usd / paid_users`
3. **Scorecards** (top): `paid_users`, `upsell_revenue_usd`, `cr_view_to_paid`, `arpu_paid`.
4. **Pivot table**: rows `upsell_version`, columns `funnel_version`, metric `paid_users`.
5. **Filter**: `geo`, `upsell_order`.
6. Title: **"Jobescape — Upsell by upsell_version × funnel_version"**

---

## After you're done

1. **Share** each dashboard:
   - Top-right → **Share** → **Manage access** → **Anyone with the link can view**
   - Copy link, paste into [`dashboards/README.md`](README.md) (replace `<your-share-link>`)

2. **Take screenshots** of each dashboard (full-page) and save into this folder as:
   - `cohort_retention.png`
   - `acquisition_funnel.png`
   - `upsell_by_segment.png`

3. Commit and push:
   ```bash
   cd ~/Downloads/jobescape-product-analytics
   git add dashboards/
   git commit -m "Add Looker Studio dashboards and screenshots"
   git push
   ```
