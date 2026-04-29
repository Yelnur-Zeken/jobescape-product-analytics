-- 03_retention_cohorts.sql
-- Cohort retention by subscribe date with two parallel definitions:
--   * Lessons-retention   — lesson_started / completed / csat events
--   * AI-Tools-retention  — ai_chat_message_* / ai_assistant_* events
--
-- Day buckets are computed via TIMESTAMP_DIFF(MINUTE) in 1440-minute steps
-- up to Day 30, with a `> 30` overflow bucket. Each user is enriched with
-- device features parsed from user_agent (Mobile / Desktop, OS, browser,
-- device-model up to iPhone 16 / Galaxy S25 / Pixel 9), plus
-- purchased_upsell, web_app, and user_path attributes.
--
-- COST SAFETY: every join to events.* uses partition predicates; run
-- with maximum_bytes_billed = 50 GB or lower.

WITH sub_event AS (
  SELECT DISTINCT
    user_id,
    device_id,
    DATE(timestamp) AS purch_date,
    JSON_VALUE(event_metadata, '$.personal_plan_pk') AS personal_plan,
    timestamp AS purch_timestamp,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.age') IS NULL
        OR JSON_VALUE(event_metadata, '$.age') = '' THEN 'other'
      ELSE JSON_VALUE(event_metadata, '$.age')
    END AS age,
    JSON_VALUE(event_metadata, '$.country_code') AS country_code,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.gender') IN ('Female','female','Mujer') THEN 'Female'
      WHEN JSON_VALUE(event_metadata, '$.gender') IN ('Male','male','Hombre') THEN 'Male'
      ELSE 'other'
    END AS gender,
    JSON_VALUE(event_metadata, '$.subscription') AS subscription,
    JSON_VALUE(event_metadata, '$.channel') AS channel,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.payment_method') = 'apple_pay' THEN 'applepay'
      ELSE JSON_VALUE(event_metadata, '$.payment_method')
    END AS payment_method,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.utm_source')
        IN ('fb_bio','fb_page','fb_post','facebook','insta_bio') THEN 'facebook'
      WHEN JSON_VALUE(event_metadata, '$.utm_source')
        IN ('TikTok','google','unionapps')
        THEN JSON_VALUE(event_metadata, '$.utm_source')
      ELSE 'other'
    END AS utm_source,
    CASE
      WHEN JSON_VALUE(event_metadata, '$.country_code')
        IN ('AE','AT','AU','BH','BN','CA','CZ','DE','DK','ES','FI','FR',
            'GB','HK','IE','IL','IT','JP','KR','NL','NO','PT','QA','SA',
            'SE','SG','SI','US','NZ')
      THEN 'T1' ELSE 'WW'
    END AS geo
  FROM `events.funnel-raw-table`
  WHERE event_name = 'pr_funnel_subscribe'
    AND JSON_VALUE(event_metadata, '$.email') NOT LIKE '%test%'
    AND JSON_VALUE(event_metadata, '$.country_code') != 'KZ'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
                            AND CURRENT_DATE()
),

unsub AS (
  SELECT DISTINCT
    user_id AS unsub_user_id,
    MIN(timestamp) AS unsub_timestamp
  FROM `events.app-raw-table`
  WHERE event_name = 'pr_webapp_unsubscribed'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                            AND CURRENT_DATE()
  GROUP BY user_id
),

-- user_path resolution chain (scale / escape / starter / simplify),
-- with a fallback through device_id for users whose path event was
-- recorded before they had a stable user_id.
device_to_user_mapping AS (
  SELECT
    device_id,
    FIRST_VALUE(user_id IGNORE NULLS) OVER (
      PARTITION BY device_id ORDER BY timestamp DESC
    ) AS mapped_user_id
  FROM `events.funnel-raw-table`
  WHERE event_name = 'pr_funnel_email_submit'
    AND user_id IS NOT NULL AND user_id != 'undefined'
    AND timestamp BETWEEN TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 180 DAY)
                      AND CURRENT_TIMESTAMP()
),
path_from_metadata AS (
  SELECT
    se.user_id,
    COALESCE(
      JSON_VALUE(frt.event_metadata, '$.scale_path'),
      JSON_VALUE(frt.event_metadata, '$.escape_path'),
      JSON_VALUE(frt.event_metadata, '$.starter_path'),
      JSON_VALUE(frt.event_metadata, '$.simplify_path')
    ) AS path_from_meta
  FROM sub_event se
  LEFT JOIN `events.funnel-raw-table` frt
    ON se.user_id = frt.user_id
   AND frt.event_name = 'pr_funnel_subscribe'
   AND frt.timestamp = se.purch_timestamp
),
path_events AS (
  SELECT
    CASE
      WHEN frt.user_id IS NOT NULL AND frt.user_id != 'undefined' THEN frt.user_id
      ELSE dm.mapped_user_id
    END AS resolved_user_id,
    CASE
      WHEN frt.event_name = 'pr_funnel_scale_path'    THEN 'scale_path'
      WHEN frt.event_name = 'pr_funnel_escape_path'   THEN 'escape_path'
      WHEN frt.event_name = 'pr_funnel_simplify_path' THEN 'simplify_path'
      WHEN frt.event_name = 'pr_funnel_starter_path'  THEN 'starter_path'
    END AS path_type,
    frt.timestamp
  FROM `events.funnel-raw-table` frt
  INNER JOIN sub_event se ON frt.device_id = se.device_id
  LEFT  JOIN device_to_user_mapping dm ON frt.device_id = dm.device_id
  WHERE frt.event_name IN ('pr_funnel_scale_path','pr_funnel_escape_path',
                           'pr_funnel_simplify_path','pr_funnel_starter_path')
    AND frt.timestamp <= se.purch_timestamp
    AND DATE(frt.timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 180 DAY)
                                AND CURRENT_DATE()
),
user_path_cte AS (
  SELECT
    se.user_id,
    COALESCE(
      pfm.path_from_meta,
      FIRST_VALUE(pe.path_type IGNORE NULLS) OVER (
        PARTITION BY se.user_id ORDER BY pe.timestamp DESC
      )
    ) AS user_path
  FROM sub_event se
  LEFT JOIN path_from_metadata pfm ON se.user_id = pfm.user_id
  LEFT JOIN path_events       pe   ON se.user_id = pe.resolved_user_id
),

-- Device parser — maps user_agent to model / browser / OS.
-- Trimmed to a representative subset; full parser ships ~80 device patterns.
registration AS (
  SELECT DISTINCT
    frt.user_id AS registration_id,
    CASE
      WHEN REGEXP_CONTAINS(user_agent,
           r'(Android|iPhone|Windows Phone|iPad|BlackBerry|webOS|Kindle)')
        THEN 'Mobile'
      WHEN REGEXP_CONTAINS(user_agent, r'(Windows NT|Macintosh|Linux|X11)')
        THEN 'Desktop'
      ELSE 'Unknown'
    END AS reg_device_type,
    CASE
      WHEN REGEXP_CONTAINS(user_agent, r'Chrome')
        AND NOT REGEXP_CONTAINS(user_agent, r'Edg|OPR') THEN 'Chrome'
      WHEN REGEXP_CONTAINS(user_agent, r'Edg')          THEN 'Edge'
      WHEN REGEXP_CONTAINS(user_agent, r'Firefox')      THEN 'Firefox'
      WHEN REGEXP_CONTAINS(user_agent, r'Safari')
        AND NOT REGEXP_CONTAINS(user_agent, r'Chrome')   THEN 'Safari'
      ELSE 'Other'
    END AS browser,
    CASE
      WHEN REGEXP_CONTAINS(user_agent, r'Android') THEN 'Android'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone|iPad|iPod') THEN 'iOS'
      WHEN REGEXP_CONTAINS(user_agent, r'Windows NT') THEN 'Windows'
      WHEN REGEXP_CONTAINS(user_agent, r'Mac OS X') THEN 'Mac OS'
      WHEN REGEXP_CONTAINS(user_agent, r'Linux') THEN 'Linux'
      ELSE 'Other'
    END AS operating_system,
    CASE
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone17,1') THEN 'iPhone16 Pro'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone17,2') THEN 'iPhone16 Pro Max'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone17,3') THEN 'iPhone16'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone17,4') THEN 'iPhone16 Plus'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone17,5') THEN 'iPhone16e'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone16,1') THEN 'iPhone15 Pro'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone16,2') THEN 'iPhone15 Pro Max'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone15,4') THEN 'iPhone15'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone15,5') THEN 'iPhone15 Plus'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone15,2') THEN 'iPhone14 Pro'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone15,3') THEN 'iPhone14 Pro Max'
      WHEN REGEXP_CONTAINS(user_agent, r'iPhone') THEN 'iPhone (generic)'
      WHEN REGEXP_CONTAINS(user_agent, r'(SM-S931B|SM-S931U)') THEN 'Samsung Galaxy S25'
      WHEN REGEXP_CONTAINS(user_agent, r'(SM-S928B/DS|SM-S928W)') THEN 'Samsung Galaxy S24 Ultra'
      WHEN REGEXP_CONTAINS(user_agent, r'(SM-S911B|SM-S911U)') THEN 'Samsung Galaxy S23'
      WHEN REGEXP_CONTAINS(user_agent, r'(SM-S901B|SM-S901U)') THEN 'Samsung Galaxy S22'
      WHEN REGEXP_CONTAINS(user_agent, r'Pixel 9 Pro') THEN 'Google Pixel 9 Pro'
      WHEN REGEXP_CONTAINS(user_agent, r'Pixel 9')     THEN 'Google Pixel 9'
      WHEN REGEXP_CONTAINS(user_agent, r'Pixel 8 Pro') THEN 'Google Pixel 8 Pro'
      WHEN REGEXP_CONTAINS(user_agent, r'Pixel 8')     THEN 'Google Pixel 8'
      ELSE 'other'
    END AS device
  FROM `events.app-raw-table` frt
  INNER JOIN sub_event se ON frt.user_id = se.user_id
  WHERE event_name = 'pr_webapp_registration_view'
    AND timestamp >= se.purch_timestamp
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                            AND CURRENT_DATE()
),

retention AS (
  SELECT user_id AS ret_user_id, timestamp AS ret_timestamp
  FROM `events.app-raw-table`
  WHERE event_name IN ('pr_webapp_lesson_started',
                       'pr_webapp_lesson_completed',
                       'pr_webapp_lesson_csat_click',
                       'pr_webapp_course_csat_click')
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                            AND CURRENT_DATE()
),
retention_ai AS (
  SELECT user_id AS ret_ai_user_id, timestamp AS ret_ai_timestamp
  FROM `events.app-raw-table`
  WHERE event_name IN ('pr_webapp_ai_chat_message_sent',
                       'pr_webapp_ai_chat_message_received',
                       'pr_webapp_ai_assistant_generate_click',
                       'pr_webapp_ai_assistant_message_received')
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                            AND CURRENT_DATE()
),
upsell AS (
  SELECT DISTINCT user_id AS upsell_user_id
  FROM `events.app-raw-table`
  WHERE event_name = 'pr_webapp_upsell_successful_purchase'
    AND DATE(timestamp) BETWEEN DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
                            AND CURRENT_DATE()
)

SELECT
  se.*,
  up.user_path,
  unsub.unsub_user_id,
  unsub.unsub_timestamp,
  CASE WHEN se.user_id IN (
    SELECT DISTINCT user_id FROM `events.app-raw-table`
    WHERE event_name = 'pr_webapp_ios_succesfully_achieved'
      AND DATE(timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
  ) THEN 'app' ELSE 'web' END AS web_app,
  ret_user_id,
  CASE
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  1440 THEN 'Day 0'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  2880 THEN 'Day 1'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  4320 THEN 'Day 2'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  5760 THEN 'Day 3'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  7200 THEN 'Day 4'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <=  8640 THEN 'Day 5'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <= 10080 THEN 'Day 6'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <= 11520 THEN 'Day 7'
    WHEN TIMESTAMP_DIFF(ret_timestamp, purch_timestamp, MINUTE) <= 44640 THEN 'Day 30'
    ELSE '> 30'
  END AS retention_day,
  ret_ai_user_id,
  CASE
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  1440 THEN 'Day 0'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  2880 THEN 'Day 1'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  4320 THEN 'Day 2'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  5760 THEN 'Day 3'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  7200 THEN 'Day 4'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <=  8640 THEN 'Day 5'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <= 10080 THEN 'Day 6'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <= 11520 THEN 'Day 7'
    WHEN TIMESTAMP_DIFF(ret_ai_timestamp, purch_timestamp, MINUTE) <= 44640 THEN 'Day 30'
    ELSE '> 30'
  END AS retention_ai_day,
  reg.device,
  reg.reg_device_type,
  reg.operating_system,
  reg.browser,
  CASE WHEN ups.upsell_user_id IS NOT NULL THEN 1 ELSE 0 END AS purchased_upsell
FROM sub_event se
LEFT JOIN retention      r    ON se.user_id = r.ret_user_id
LEFT JOIN retention_ai   rai  ON se.user_id = rai.ret_ai_user_id
LEFT JOIN registration   reg  ON se.user_id = reg.registration_id
LEFT JOIN user_path_cte  up   ON se.user_id = up.user_id
LEFT JOIN upsell         ups  ON se.user_id = ups.upsell_user_id
LEFT JOIN unsub               ON se.user_id = unsub.unsub_user_id
;
