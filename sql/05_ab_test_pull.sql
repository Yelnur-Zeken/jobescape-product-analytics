-- 05_ab_test_pull.sql
-- Pull data for the new paywall A/B test from the ab_tests dataset
-- so it can be analyzed in Python (see notebooks/04_ab_test_significance.ipynb).

DECLARE test_name_filter STRING DEFAULT 'paywall_v2_test';
DECLARE start_date DATE DEFAULT '2026-04-01';
DECLARE end_date   DATE DEFAULT '2026-04-21';

SELECT
  test_id,
  test_name,
  test_version,                  -- 'control' | 'variant'
  DATE(date)        AS test_date,
  criterion,
  metric_name,                   -- e.g. 'paywall_view', 'trial_start'
  metric_values                  -- cumulative metric value
FROM `ab_tests.ab_tests`
WHERE test_name = test_name_filter
  AND DATE(date) BETWEEN start_date AND end_date
ORDER BY test_date, test_version, metric_name;
