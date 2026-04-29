-- 04_upsell_user_level.sql
-- User-level pull for upsell A/B tests. Joins:
--   * funnel-raw-table (pr_funnel_subscribe — cohort entry)
--   * app-raw-table   (registration view, upsell view / TTP / purchase, unsubscribe)
--   * payments.all_payments_prod (settled upsell payments by rebill_count)
--   * intercom_tickets (refund-tagged conversations, joined by email)
--
-- Two split keys are recognized for the experiment:
--   1) JSON_VALUE(ups_view.event_metadata, '$.upsell_version')
--   2) regex extract from referrer URL (?upsell_version=...)
--
-- Filter set is the team standard: country_code != 'KZ',
-- card_type NOT IN ('PREPAID'), channel = 'primer'.
--
-- Output goes to a Pandas DataFrame and is then converted to user-level
-- (see notebooks/04_ab_test_bootstrap.ipynb -> convert_to_user_level).

WITH upsell_purch_cash AS (
  SELECT
    app.customer_account_id,
    app.rebill_count,
    SUM(app.amount) / 100 AS purch_amount,
    COUNT(*)              AS purch_count
  FROM `payments.all_payments_prod` app
  WHERE TIMESTAMP_MICROS(app.created_at) >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
    AND app.status        = 'settled'
    AND app.payment_type  = 'upsell'
    AND app.rebill_count IN (-14, -20, -22)
  GROUP BY app.customer_account_id, app.rebill_count
),

upsell_declined_insufficient AS (
  SELECT
    customer_account_id,
    rebill_count,
    COUNT(*)                            AS declined_count,
    MIN(TIMESTAMP_MICROS(created_at))   AS first_declined_at
  FROM `payments.all_payments_prod`
  WHERE rebill_count   IN (-14, -20, -22)
    AND payment_type   = 'upsell'
    AND status         = 'declined'
    AND DATE(TIMESTAMP_MICROS(created_at))
        BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY) AND CURRENT_DATE()
    AND LOWER(decline_message) LIKE LOWER('Insufficient Funds')
  GROUP BY customer_account_id, rebill_count
),

intercom_tickets AS (
  SELECT
    author_email,
    COUNT(DISTINCT conversation_id) AS ticket_count
  FROM `analytics_draft.intercom_tickets`
  WHERE LOWER(tag_name) LIKE '%upsell refund%'
  GROUP BY author_email
),

insufficient_fund_view AS (
  SELECT user_id,
         MIN(timestamp) AS first_insufficient_view_at,
         COUNT(*)       AS insufficient_view_count
  FROM `events.app-raw-table`
  WHERE event_name = 'pr_webapp_upsell_insufficient_fund_view'
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY user_id
),

insufficient_fund_click AS (
  SELECT user_id,
         MIN(timestamp) AS first_insufficient_click_at,
         COUNT(*)       AS insufficient_click_count
  FROM `events.app-raw-table`
  WHERE event_name = 'pr_webapp_upsell_insufficient_fund_click'
    AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  GROUP BY user_id
)

SELECT DISTINCT
  fun.timestamp,
  JSON_VALUE(fun.event_metadata, '$.subscription')   AS subscription,
  JSON_VALUE(fun.event_metadata, '$.channel')        AS channel,
  CASE
    WHEN JSON_VALUE(fun.event_metadata, '$.country_code')
      IN ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
          'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
          'SE','SG','SI','US','NZ')
    THEN 'T1' ELSE 'WW'
  END AS geo,
  JSON_VALUE(fun.event_metadata, '$.payment_method') AS payment_method,
  JSON_VALUE(fun.event_metadata, '$.utm_source')     AS utm_source,
  JSON_VALUE(fun.event_metadata, '$.subscription_id') AS subscription_id,
  JSON_VALUE(fun.event_metadata, '$.funnel_version')  AS funnel_version,
  JSON_VALUE(fun.event_metadata, '$.quiz_version')    AS quiz_version,
  COALESCE(
    JSON_VALUE(ups_view.event_metadata, '$.upsell_version'),
    REGEXP_EXTRACT(ups_view.referrer, r'[?&]upsell_version=([^&]+)')
  ) AS split,
  JSON_VALUE(ups_view.event_metadata,   '$.upsell_order')  AS upsell_order,
  JSON_VALUE(ups_purch.event_metadata,  '$.upsell_amount') AS upsell_amount,
  fun.user_id,
  CASE WHEN ups_view.event_id   IS NULL THEN 0 ELSE 1 END AS ups_view,
  CASE WHEN ups_ttp.event_id    IS NULL THEN 0 ELSE 1 END AS ups_ttp,
  CASE WHEN ups_purch.event_id  IS NULL THEN 0 ELSE 1 END AS ups_purched,
  CASE WHEN ifv.user_id         IS NOT NULL THEN 1 ELSE 0 END AS has_insufficient_fund_view,
  CASE WHEN ifc.user_id         IS NOT NULL THEN 1 ELSE 0 END AS has_insufficient_fund_click,
  CASE
    WHEN ups_purch.event_id IS NOT NULL
     AND unsub.event_id     IS NOT NULL
     AND TIMESTAMP_DIFF(unsub.timestamp, fun.timestamp, HOUR) <= 12
    THEN 1 ELSE 0
  END AS unsub12h,
  cash.purch_count,
  cash.purch_amount,
  it.ticket_count,
  CASE
    WHEN it.ticket_count IS NOT NULL AND it.ticket_count > 0 THEN 1 ELSE 0
  END AS is_ticket,
  di.declined_count,
  di.first_declined_at,
  CASE
    WHEN ups_purch.event_id IS NOT NULL
     AND (ifc.user_id IS NOT NULL
          OR JSON_VALUE(ups_ttp.event_metadata, '$.insufficient_fund') = 'true')
    THEN 1 ELSE 0
  END AS is_insufficient_fund_purchase
FROM `events.funnel-raw-table` fun
INNER JOIN `events.app-raw-table` reg
  ON  reg.event_name = 'pr_webapp_registration_signup_click'
  AND reg.user_id    = fun.user_id
LEFT JOIN `events.app-raw-table` ups_view
  ON  ups_view.event_name = 'pr_webapp_upsell_view'
  AND JSON_VALUE(ups_view.query_parameters, '$.source') = 'register'
  AND ups_view.user_id = fun.user_id
LEFT JOIN `events.app-raw-table` ups_ttp
  ON  ups_ttp.event_name = 'pr_webapp_upsell_purchase_click'
  AND JSON_VALUE(ups_ttp.query_parameters, '$.source') = 'register'
  AND ups_ttp.user_id = fun.user_id
  AND JSON_VALUE(ups_ttp.event_metadata, '$.upsell_order')
      = JSON_VALUE(ups_view.event_metadata, '$.upsell_order')
LEFT JOIN `events.app-raw-table` ups_purch
  ON  ups_purch.event_name = 'pr_webapp_upsell_successful_purchase'
  AND JSON_VALUE(ups_purch.query_parameters, '$.source') = 'register'
  AND ups_purch.user_id = fun.user_id
  AND JSON_VALUE(ups_purch.event_metadata, '$.upsell_order')
      = JSON_VALUE(ups_view.event_metadata, '$.upsell_order')
LEFT JOIN `events.app-raw-table` unsub
  ON unsub.user_id = fun.user_id
 AND unsub.event_name = 'pr_webapp_unsubscribed'
LEFT JOIN upsell_purch_cash cash
  ON cash.customer_account_id = ups_purch.user_id
 AND (
   (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '1' AND cash.rebill_count = -14)
   OR
   (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '2' AND cash.rebill_count IN (-20, -22))
 )
LEFT JOIN upsell_declined_insufficient di
  ON ups_purch.user_id = di.customer_account_id
 AND (
   (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '1' AND di.rebill_count = -14)
   OR
   (JSON_VALUE(ups_view.event_metadata, '$.upsell_order') = '2' AND di.rebill_count IN (-20, -22))
 )
LEFT JOIN intercom_tickets it
  ON  JSON_VALUE(fun.event_metadata, '$.email') = it.author_email
  AND JSON_VALUE(fun.event_metadata, '$.email') IS NOT NULL
  AND JSON_VALUE(fun.event_metadata, '$.email') != ''
LEFT JOIN insufficient_fund_view  ifv ON fun.user_id = ifv.user_id
LEFT JOIN insufficient_fund_click ifc ON fun.user_id = ifc.user_id
WHERE fun.event_name = 'pr_funnel_subscribe'
  AND JSON_VALUE(fun.event_metadata, '$.country_code') != 'KZ'
  AND DATE(fun.timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
  AND ups_view.ip != '45.8.117.97'
  AND JSON_VALUE(fun.event_metadata, '$.card_type') NOT IN ('PREPAID')
  AND JSON_VALUE(fun.event_metadata, '$.channel') = 'primer'
;
