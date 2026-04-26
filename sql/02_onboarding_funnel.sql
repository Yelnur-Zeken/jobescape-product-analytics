-- 02_onboarding_funnel.sql
-- Acquisition funnel from first quiz path event to paid subscription.
-- Steps:
--   path_selected  -> email_submit  -> subscribe  -> registration_signup_click  -> upsell_view
--
-- Output: per-day step counts and step-to-step conversion rates,
-- sliceable by funnel_version and geo (T1 / WW).

-- ⚠️ COST SAFETY: 14-day default window. Do not extend without dry-run check.
DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY);
DECLARE end_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

WITH funnel_events AS (
  SELECT
    user_id,
    device_id,
    event_name,
    timestamp,
    DATE(timestamp)                                   AS event_date,
    country_code,
    JSON_VALUE(event_metadata, '$.funnel_version')    AS funnel_version
  FROM `events.funnel-raw-table`
  WHERE event_name IN (
          'pr_funnel_scale_path',
          'pr_funnel_escape_path',
          'pr_funnel_simplify_path',
          'pr_funnel_starter_path',
          'pr_funnel_email_submit',
          'pr_funnel_subscribe'
        )
    AND country_code != 'KZ'
    AND timestamp BETWEEN start_ts AND end_ts
),

webapp_events AS (
  SELECT
    user_id,
    event_name,
    timestamp,
    DATE(timestamp) AS event_date
  FROM `events.app-raw-table`
  WHERE event_name IN (
          'pr_webapp_registration_signup_click',
          'pr_webapp_upsell_view'
        )
    AND timestamp BETWEEN start_ts AND end_ts
)

SELECT
  COALESCE(f.event_date, w.event_date)                                       AS event_date,
  ANY_VALUE(f.funnel_version)                                                AS funnel_version,
  COUNT(DISTINCT IF(f.event_name LIKE 'pr_funnel_%_path', f.device_id, NULL)) AS s1_path_selected,
  COUNT(DISTINCT IF(f.event_name = 'pr_funnel_email_submit',  f.user_id, NULL)) AS s2_email_submit,
  COUNT(DISTINCT IF(f.event_name = 'pr_funnel_subscribe',     f.user_id, NULL)) AS s3_subscribe,
  COUNT(DISTINCT IF(w.event_name = 'pr_webapp_registration_signup_click', w.user_id, NULL)) AS s4_signup,
  COUNT(DISTINCT IF(w.event_name = 'pr_webapp_upsell_view',   w.user_id, NULL)) AS s5_upsell_view
FROM funnel_events f
FULL OUTER JOIN webapp_events w
  ON f.user_id = w.user_id
 AND f.event_date = w.event_date
GROUP BY event_date
ORDER BY event_date DESC;

-- Adjacent step-to-step conversion (use this in Looker Studio with calculated fields):
--   cr_path_to_email   = s2_email_submit / s1_path_selected
--   cr_email_to_sub    = s3_subscribe    / s2_email_submit
--   cr_sub_to_signup   = s4_signup       / s3_subscribe
--   cr_signup_to_upsell= s5_upsell_view  / s4_signup
