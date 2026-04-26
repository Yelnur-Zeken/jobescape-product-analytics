-- 01_data_exploration.sql
-- Quick volumetric and freshness check on the raw event table.
-- Useful as a smoke test before any heavier analysis.

-- 1. Daily event volume for the last 30 days
SELECT
  DATE(timestamp)            AS event_date,
  COUNT(*)                   AS events_total,
  COUNT(DISTINCT user_id)    AS users_active,
  COUNT(DISTINCT device_id)  AS devices_active
FROM `hopeful-list-429812-f3.events.app_raw_table`
WHERE DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
                          AND CURRENT_DATE()
GROUP BY event_date
ORDER BY event_date DESC;

-- 2. Top 20 event names
SELECT
  event_name,
  COUNT(*) AS occurrences
FROM `hopeful-list-429812-f3.events.app_raw_table`
WHERE DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                          AND CURRENT_DATE()
GROUP BY event_name
ORDER BY occurrences DESC
LIMIT 20;

-- 3. Country breakdown
SELECT
  country,
  COUNT(DISTINCT user_id) AS active_users
FROM `hopeful-list-429812-f3.events.app_raw_table`
WHERE DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 14 DAY)
                          AND CURRENT_DATE()
GROUP BY country
ORDER BY active_users DESC
LIMIT 20;
