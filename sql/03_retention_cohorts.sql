-- 03_retention_cohorts.sql
-- D1 / D3 / D5 / D7 retention cohorts for paid subscribers.
-- Cohort start event: pr_funnel_subscribe (the moment a user starts a paid trial).
-- A user is "retained on day N" if any pr_webapp_* event is recorded for them
-- on cohort_date + N days.
--
-- Output: one row per cohort_date with cohort_size and four retention rates,
-- broken down by geo (T1 / WW) and platform (iOS / Android).

-- ⚠️ COST SAFETY: events.app-raw-table is partitioned by DATE(timestamp).
-- The WHERE-clause partition predicate below is REQUIRED for partition pruning.
-- Default lookback is 14 days. Increase carefully if needed.
DECLARE lookback_days INT64 DEFAULT 14;
DECLARE start_ts TIMESTAMP DEFAULT TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL lookback_days DAY);
DECLARE end_ts   TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

WITH cohorts AS (
  SELECT
    user_id,
    DATE(MIN(timestamp))                                AS cohort_date,
    ANY_VALUE(
      CASE
        WHEN JSON_VALUE(event_metadata, '$.country_code') IN
             ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
              'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
              'SE','SG','SI','US','NZ')
        THEN 'T1' ELSE 'WW'
      END
    )                                                   AS geo,
    ANY_VALUE(
      CASE
        WHEN LOWER(user_agent) LIKE '%iphone%' OR LOWER(user_agent) LIKE '%ipad%' OR LOWER(user_agent) LIKE '%ios%'
          THEN 'iOS'
        WHEN LOWER(user_agent) LIKE '%android%'
          THEN 'Android'
        ELSE 'Other'
      END
    )                                                   AS platform
  FROM `events.funnel-raw-table`
  WHERE event_name = 'pr_funnel_subscribe'
    AND country_code != 'KZ'
    AND timestamp BETWEEN start_ts AND end_ts
    AND user_id IS NOT NULL
    AND user_id != 'undefined'
  GROUP BY user_id
),

activity AS (
  SELECT
    a.user_id,
    DATE_DIFF(DATE(a.timestamp), c.cohort_date, DAY) AS day_n
  FROM `events.app-raw-table` a
  JOIN cohorts c USING (user_id)
  WHERE a.event_name LIKE 'pr_webapp_%'
    AND DATE(a.timestamp) BETWEEN c.cohort_date
                              AND DATE_ADD(c.cohort_date, INTERVAL 7 DAY)
)

SELECT
  c.cohort_date,
  c.geo,
  c.platform,
  COUNT(DISTINCT c.user_id)                          AS cohort_size,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 1, a.user_id, NULL)),
    COUNT(DISTINCT c.user_id)
  )                                                  AS retention_d1,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 3, a.user_id, NULL)),
    COUNT(DISTINCT c.user_id)
  )                                                  AS retention_d3,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 5, a.user_id, NULL)),
    COUNT(DISTINCT c.user_id)
  )                                                  AS retention_d5,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 7, a.user_id, NULL)),
    COUNT(DISTINCT c.user_id)
  )                                                  AS retention_d7
FROM cohorts c
LEFT JOIN activity a USING (user_id)
GROUP BY cohort_date, geo, platform
ORDER BY cohort_date DESC, geo, platform;
