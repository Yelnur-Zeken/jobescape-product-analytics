-- 03_retention_cohorts.sql
-- D1 / D3 / D5 / D7 retention cohorts by install date.
-- Output: one row per install_date (cohort) with cohort_size and four retention rates.

DECLARE lookback_days INT64 DEFAULT 60;

WITH installs AS (
  SELECT
    user_id,
    DATE(MIN(timestamp))       AS install_date,
    ANY_VALUE(country)         AS country
  FROM `hopeful-list-429812-f3.events.app_raw_table`
  WHERE event_name = 'app_install'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL lookback_days DAY)
                            AND CURRENT_DATE()
  GROUP BY user_id
),

activity AS (
  SELECT
    e.user_id,
    DATE(e.timestamp)                                  AS activity_date,
    DATE_DIFF(DATE(e.timestamp), i.install_date, DAY)  AS day_n
  FROM `hopeful-list-429812-f3.events.app_raw_table` e
  JOIN installs i USING (user_id)
  WHERE DATE(e.timestamp) BETWEEN i.install_date
                              AND DATE_ADD(i.install_date, INTERVAL 7 DAY)
)

SELECT
  i.install_date                                      AS cohort_date,
  COUNT(DISTINCT i.user_id)                           AS cohort_size,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 1, a.user_id, NULL)),
    COUNT(DISTINCT i.user_id)
  )                                                   AS retention_d1,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 3, a.user_id, NULL)),
    COUNT(DISTINCT i.user_id)
  )                                                   AS retention_d3,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 5, a.user_id, NULL)),
    COUNT(DISTINCT i.user_id)
  )                                                   AS retention_d5,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(a.day_n = 7, a.user_id, NULL)),
    COUNT(DISTINCT i.user_id)
  )                                                   AS retention_d7
FROM installs i
LEFT JOIN activity a USING (user_id)
GROUP BY cohort_date
ORDER BY cohort_date;
