-- 01_data_exploration.sql
-- Smoke-test queries on the raw event tables before any deeper analysis.
-- Run inside billing project `hopeful-list-429812-f3`.
--
-- ⚠️ COST SAFETY:
--   * Run queries one at a time, NOT all at once (BigQuery Console runs only
--     the highlighted text — select one block, click Run).
--   * Always check the dry-run estimate (top-right "This query will process
--     N MB / GB") BEFORE clicking Run. If estimate > 5 GB, abort.
--   * Default windows below are short (14 / 30 days). Do not extend without
--     re-checking the dry-run estimate.

-- 1. Daily subscription volume for the last 30 days (excluding KZ traffic).
SELECT
  DATE(timestamp)              AS event_date,
  COUNT(*)                     AS subscribes,
  COUNT(DISTINCT user_id)      AS unique_users
FROM `events.funnel-raw-table`
WHERE event_name = 'pr_funnel_subscribe'
  AND country_code != 'KZ'
  AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                          AND CURRENT_DATE()
GROUP BY event_date
ORDER BY event_date DESC;

-- 2. Top 25 event names in the funnel table (last 14 days).
SELECT
  event_name,
  COUNT(*) AS occurrences
FROM `events.funnel-raw-table`
WHERE timestamp BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
                   AND CURRENT_TIMESTAMP()
GROUP BY event_name
ORDER BY occurrences DESC
LIMIT 25;

-- 3. Geo split T1 vs WW for paid subscriptions.
SELECT
  CASE
    WHEN JSON_VALUE(event_metadata, '$.country_code') IN
         ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
          'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
          'SE','SG','SI','US','NZ')
    THEN 'T1' ELSE 'WW'
  END                                AS geo,
  COUNT(*)                           AS subscribes
FROM `events.funnel-raw-table`
WHERE event_name = 'pr_funnel_subscribe'
  AND country_code != 'KZ'
  AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                          AND CURRENT_DATE()
GROUP BY geo
ORDER BY subscribes DESC;

-- 4. Upsell view volume by upsell_version (last 14 days).
SELECT
  COALESCE(
    JSON_VALUE(event_metadata, '$.upsell_version'),
    REGEXP_EXTRACT(referrer, r'[?&]upsell_version=([^&]+)')
  ) AS upsell_version,
  COUNT(DISTINCT user_id) AS users
FROM `events.app-raw-table`
WHERE event_name = 'pr_webapp_upsell_view'
  AND timestamp BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 14 DAY)
                   AND CURRENT_TIMESTAMP()
  AND JSON_VALUE(query_parameters, '$.source') = 'register'
GROUP BY upsell_version
ORDER BY users DESC
LIMIT 20;
