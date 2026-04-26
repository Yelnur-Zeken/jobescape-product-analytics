-- 04_upsell_by_segment.sql
-- Upsell performance for users from new creatives + new acquisition funnel
-- vs the baseline. Joins funnel events, webapp upsell events, and the
-- payments.all_payments_prod cash table.
--
-- Output:
--   * exposed_users      — users who saw the upsell page
--   * ttp_clicks         — users who clicked "purchase" on the upsell
--   * paid_users         — users with a settled upsell payment
--   * unsub_12h_users    — paid users who unsubscribed within 12h
--   * upsell_revenue_usd — sum of settled upsell amounts (in USD)
--   * upsell_gain        — upsell_revenue_usd / paid_users (avg revenue per paid upsell user)
--   * cr_view_to_paid    — paid_users / exposed_users
--
-- ⚠️ COST SAFETY: This query has multiple LEFT JOINs to events.app-raw-table.
-- The `start_ts` filter is applied to `fun.timestamp` AND `ups_view.timestamp`
-- to enable partition pruning on both joined sides. Do NOT remove either.
-- Run this ONLY with a narrow window (5-7 days). Always check dry-run estimate
-- in the BigQuery Console before clicking Run.
--
-- Adjust `start_ts`, `upsell_versions` for your window.

DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 7 DAY);
DECLARE upsell_versions ARRAY<STRING> DEFAULT ['u15.4.0','u15.4.5'];

WITH upsell_payments AS (
  SELECT
    customer_account_id,
    rebill_count,
    SUM(amount) / 100   AS upsell_amount_usd,
    COUNT(*)            AS upsell_payment_count
  FROM `payments.all_payments_prod`
  WHERE TIMESTAMP_MICROS(created_at) >= start_ts
    AND status        = 'settled'
    AND payment_type  = 'upsell'
    AND rebill_count IN (-14, -20, -22)
  GROUP BY customer_account_id, rebill_count
),

base AS (
  SELECT
    fun.user_id,
    fun.timestamp                                                         AS subscribe_ts,
    JSON_VALUE(fun.event_metadata, '$.funnel_version')                    AS funnel_version,
    CASE
      WHEN JSON_VALUE(fun.event_metadata, '$.country_code') IN
           ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
            'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
            'SE','SG','SI','US','NZ')
      THEN 'T1' ELSE 'WW'
    END                                                                   AS geo,
    COALESCE(
      JSON_VALUE(ups_view.event_metadata, '$.upsell_version'),
      REGEXP_EXTRACT(ups_view.referrer, r'[?&]upsell_version=([^&]+)')
    )                                                                     AS upsell_version,
    JSON_VALUE(ups_view.event_metadata, '$.upsell_order')                 AS upsell_order,
    ups_view.event_id                                                     AS upsell_view_id,
    ups_ttp.event_id                                                      AS upsell_ttp_id,
    ups_purch.event_id                                                    AS upsell_purch_id,
    unsub.timestamp                                                       AS unsub_ts,
    cash.upsell_amount_usd
  FROM `events.funnel-raw-table` fun
  LEFT JOIN `events.app-raw-table` ups_view
    ON  ups_view.event_name = 'pr_webapp_upsell_view'
    AND ups_view.user_id    = fun.user_id
    AND ups_view.timestamp >= start_ts                                  -- partition prune
    AND JSON_VALUE(ups_view.query_parameters, '$.source') = 'register'
  LEFT JOIN `events.app-raw-table` ups_ttp
    ON  ups_ttp.event_name  = 'pr_webapp_upsell_purchase_click'
    AND ups_ttp.user_id     = fun.user_id
    AND ups_ttp.timestamp >= start_ts                                   -- partition prune
    AND JSON_VALUE(ups_ttp.query_parameters, '$.source') = 'register'
    AND JSON_VALUE(ups_ttp.event_metadata,   '$.upsell_order') =
        JSON_VALUE(ups_view.event_metadata, '$.upsell_order')
  LEFT JOIN `events.app-raw-table` ups_purch
    ON  ups_purch.event_name = 'pr_webapp_upsell_successful_purchase'
    AND ups_purch.user_id    = fun.user_id
    AND ups_purch.timestamp >= start_ts                                 -- partition prune
    AND JSON_VALUE(ups_purch.query_parameters, '$.source') = 'register'
    AND JSON_VALUE(ups_purch.event_metadata,   '$.upsell_order') =
        JSON_VALUE(ups_view.event_metadata,   '$.upsell_order')
  LEFT JOIN `events.app-raw-table` unsub
    ON  unsub.event_name = 'pr_webapp_unsubscribed'
    AND unsub.user_id    = fun.user_id
    AND unsub.timestamp >= start_ts                                     -- partition prune
  LEFT JOIN upsell_payments cash
    ON  cash.customer_account_id = ups_purch.user_id
    AND (
      (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '1' AND cash.rebill_count IN (-14)) OR
      (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '2' AND cash.rebill_count IN (-20, -22))
    )
  WHERE fun.event_name = 'pr_funnel_subscribe'
    AND fun.country_code != 'KZ'
    AND fun.timestamp >= start_ts
    AND ups_view.timestamp >= start_ts
    AND COALESCE(
          JSON_VALUE(ups_view.event_metadata, '$.upsell_version'),
          REGEXP_EXTRACT(ups_view.referrer, r'[?&]upsell_version=([^&]+)')
        ) IN UNNEST(upsell_versions)
    AND JSON_VALUE(fun.event_metadata, '$.card_type') NOT IN ('PREPAID')
    AND JSON_VALUE(fun.event_metadata, '$.channel') = 'primer'
)

SELECT
  upsell_version,
  funnel_version,
  geo,
  upsell_order,
  COUNT(DISTINCT user_id)                                              AS subscribers,
  COUNT(DISTINCT IF(upsell_view_id  IS NOT NULL, user_id, NULL))       AS exposed_users,
  COUNT(DISTINCT IF(upsell_ttp_id   IS NOT NULL, user_id, NULL))       AS ttp_clicks,
  COUNT(DISTINCT IF(upsell_purch_id IS NOT NULL, user_id, NULL))       AS paid_users,
  COUNT(DISTINCT IF(
    upsell_purch_id IS NOT NULL
    AND unsub_ts IS NOT NULL
    AND TIMESTAMP_DIFF(unsub_ts, subscribe_ts, HOUR) <= 12,
    user_id, NULL
  ))                                                                   AS unsub_12h_users,
  SUM(IFNULL(upsell_amount_usd, 0))                                    AS upsell_revenue_usd,
  SAFE_DIVIDE(
    SUM(IFNULL(upsell_amount_usd, 0)),
    COUNT(DISTINCT IF(upsell_purch_id IS NOT NULL, user_id, NULL))
  )                                                                    AS upsell_gain,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(upsell_purch_id IS NOT NULL, user_id, NULL)),
    COUNT(DISTINCT IF(upsell_view_id  IS NOT NULL, user_id, NULL))
  )                                                                    AS cr_view_to_paid
FROM base
GROUP BY upsell_version, funnel_version, geo, upsell_order
ORDER BY upsell_version, funnel_version, geo, upsell_order;
