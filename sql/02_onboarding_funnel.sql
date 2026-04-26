-- 02_onboarding_funnel.sql
-- Onboarding funnel: per-step user counts and step-to-step conversion.
-- Steps: app_open -> onboarding_start -> goal_selected -> level_selected
--        -> personalization_done -> paywall_view -> trial_start

DECLARE start_date DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY);
DECLARE end_date   DATE DEFAULT CURRENT_DATE();

WITH onboarding AS (
  SELECT
    user_id,
    event_name,
    JSON_VALUE(event_metadata, '$.step_name') AS step_name,
    timestamp
  FROM `hopeful-list-429812-f3.events.app_raw_table`
  WHERE event_name IN (
    'app_open',
    'onboarding_start',
    'goal_selected',
    'level_selected',
    'personalization_done',
    'paywall_view',
    'trial_start'
  )
    AND DATE(timestamp) BETWEEN start_date AND end_date
),

per_step AS (
  SELECT
    COUNT(DISTINCT IF(event_name='app_open',             user_id, NULL)) AS s0_open,
    COUNT(DISTINCT IF(event_name='onboarding_start',     user_id, NULL)) AS s1_start,
    COUNT(DISTINCT IF(event_name='goal_selected',        user_id, NULL)) AS s2_goal,
    COUNT(DISTINCT IF(event_name='level_selected',       user_id, NULL)) AS s3_level,
    COUNT(DISTINCT IF(event_name='personalization_done', user_id, NULL)) AS s4_personalize,
    COUNT(DISTINCT IF(event_name='paywall_view',         user_id, NULL)) AS s5_paywall,
    COUNT(DISTINCT IF(event_name='trial_start',          user_id, NULL)) AS s6_trial
  FROM onboarding
)

SELECT
  s0_open,
  s1_start, SAFE_DIVIDE(s1_start, s0_open) AS cr_open_to_start,
  s2_goal,  SAFE_DIVIDE(s2_goal,  s1_start) AS cr_start_to_goal,
  s3_level, SAFE_DIVIDE(s3_level, s2_goal)  AS cr_goal_to_level,
  s4_personalize, SAFE_DIVIDE(s4_personalize, s3_level)      AS cr_level_to_personalize,
  s5_paywall,     SAFE_DIVIDE(s5_paywall,     s4_personalize) AS cr_personalize_to_paywall,
  s6_trial,       SAFE_DIVIDE(s6_trial,       s5_paywall)     AS cr_paywall_to_trial
FROM per_step;
