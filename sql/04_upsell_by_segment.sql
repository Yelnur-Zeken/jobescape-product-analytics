-- 04_upsell_by_segment.sql
-- Upsell performance for users acquired via new creatives + new acquisition funnel
-- vs the baseline. Uses attribution_id from events to join with facebook_ads (Fivetran).
--
-- Metrics:
--   * paying_users
--   * upsell_gain      = upsell_revenue / first_purchase_revenue
--   * arpu_90d         = sum(payment_amount within first 90 days) / paying_users

DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY);
DECLARE end_date   DATE DEFAULT CURRENT_DATE();

WITH attributed_users AS (
  SELECT DISTINCT
    e.user_id,
    e.attribution_id,
    DATE(MIN(e.timestamp)) OVER (PARTITION BY e.user_id) AS install_date,
    JSON_VALUE(e.user_metadata, '$.creative_group')      AS creative_group,
    JSON_VALUE(e.user_metadata, '$.funnel_version')      AS funnel_version
  FROM `hopeful-list-429812-f3.events.app_raw_table` e
  WHERE e.event_name = 'app_install'
    AND DATE(e.timestamp) BETWEEN start_date AND end_date
),

segmented AS (
  SELECT
    user_id,
    install_date,
    CASE
      WHEN creative_group = 'new_creative_v2' AND funnel_version = 'funnel_v3'
        THEN 'new_creative_new_funnel'
      ELSE 'baseline'
    END AS segment
  FROM attributed_users
),

payments_window AS (
  SELECT
    p.user_id,
    p.payment_id,
    p.payment_amount_usd,
    p.payment_type,                          -- 'first_purchase' | 'upsell' | 'renewal'
    p.payment_date
  FROM `hopeful-list-429812-f3.payments.payments` p
  JOIN segmented s USING (user_id)
  WHERE p.payment_date BETWEEN s.install_date
                          AND DATE_ADD(s.install_date, INTERVAL 90 DAY)
)

SELECT
  s.segment,
  COUNT(DISTINCT s.user_id)                                          AS users,
  COUNT(DISTINCT p.user_id)                                          AS paying_users,
  SAFE_DIVIDE(COUNT(DISTINCT p.user_id), COUNT(DISTINCT s.user_id))  AS conversion_rate,
  SUM(IF(p.payment_type = 'first_purchase', p.payment_amount_usd, 0)) AS first_purchase_rev,
  SUM(IF(p.payment_type = 'upsell',         p.payment_amount_usd, 0)) AS upsell_rev,
  SAFE_DIVIDE(
    SUM(IF(p.payment_type = 'upsell', p.payment_amount_usd, 0)),
    SUM(IF(p.payment_type = 'first_purchase', p.payment_amount_usd, 0))
  )                                                                  AS upsell_gain,
  SAFE_DIVIDE(SUM(p.payment_amount_usd), COUNT(DISTINCT p.user_id))  AS arpu_90d
FROM segmented s
LEFT JOIN payments_window p USING (user_id)
GROUP BY s.segment
ORDER BY s.segment;
