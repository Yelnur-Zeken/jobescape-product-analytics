# Dashboards

Tableau dashboards built on top of BigQuery custom queries with Extract Data
caching enabled to control cost.

## Tableau

| File | Dashboard | Source query |
|---|---|---|
| `fig03_tableau_retention_cohort_lines.png` | Retention — Cohort Day Distribution (D1 / D2 / D3 / D7 by purch_date) | `sql/03_retention_cohorts.sql` |
| `fig04_tableau_retention_table.png` | Retention — Table View (D0–D7 % by purch_date) | `sql/03_retention_cohorts.sql` |
| `fig05_tableau_retention_distribution.png` | Retention — Decay curve D0 → D30+ | `sql/03_retention_cohorts.sql` |
| `fig06_tableau_upsell_gain_geo.png` | Upsell Gain by GEO + Traffic Composition | `sql/04_upsell_user_level.sql` |
| `fig07_tableau_ab_test_comparison.png` | A/B test comparison u15.3.0 / u15.3.1 / u15.4.0 / u15.4.1 (Absolute + Relative Values) | `sql/06_upsell_ab_test_u15_3_vs_u15_4.sql` |

Each Tableau dashboard exposes the same set of filters: subscription,
utm_source, geo, payment_method, channel, age, gender, personal_plan,
quiz_version, upsell_order, user_path, device, country_code.

## BigQuery (raw evidence)

| File | Description |
|---|---|
| `fig01_bq_schema_app_raw.png` | `events.app-raw-table` schema (event_id, device_id, user_id, event_name, timestamp, JSON metadata columns) |
| `fig02_bq_query_results.png` | Sample SELECT result — 1 533 rows, 117.82 GB processed |
| `fig08_bq_execution_graph.png` | Execution graph for the upsell A/B test pull (main CTE `upsell_purch_cash` and downstream stages) |
| `fig09_bq_execution_details.png` | Execution details — 11.33 sec elapsed, 1 hr 12 min slot time, 312.76 MB shuffled, 0 B spilled |

## Cost safety

All Tableau data sources use Extract Data caching with daily refresh, so
charts do not re-query BigQuery on every interaction. Custom Queries are
written with partition predicates on every join to `events.*` and run
under a `maximum_bytes_billed` cap (50–200 GB depending on date window).
