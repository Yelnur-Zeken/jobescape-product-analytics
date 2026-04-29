# Jobescape — Product Analytics Internship

Industrial internship deliverables — Big Data Analysis, Astana IT University.

- **Student:** Yelnur Zekenov (BDA-2305, ID 230539)
- **Company:** Nomad Ventures Ltd. (product: Jobescape)
- **Department:** Product Analytics
- **Workplace supervisor:** Islam Yerulanuly Mukhammedrakhym, Director of Product (official)
- **Technical supervisor:** Mirlan Tuleugaliev, Data Analyst (day-to-day mentor)
- **Academic supervisor:** Adilet Duman, Astana IT University
- **Period:** 9 March 2026 — 2 May 2026 (8 weeks)

## What's in this repo

The five deliverables of the internship:

1. **Cohort retention analysis** with two parallel definitions —
   Lessons-retention (`pr_webapp_lesson_*`) and AI-Tools-retention
   (`pr_webapp_ai_chat_*`, `pr_webapp_ai_assistant_*`) —
   segmented by geo, plan, age, gender, user_path, and a user-agent
   parser that resolves devices up to iPhone 16 / Galaxy S25 / Pixel 9.
   See [`sql/03_retention_cohorts.sql`](sql/03_retention_cohorts.sql) and
   the Tableau screenshots in [`dashboards/`](dashboards/).

2. **Upsell performance dashboard** in Tableau — Upsell Gain and Median
   Time to TTP by GEO (T1 / WW), with a Traffic Composition stack by
   subscription plan (1Week / 4Week / 12Week / 3Month-Apple). The
   underlying pull is [`sql/04_upsell_user_level.sql`](sql/04_upsell_user_level.sql).

3. **Statistical analysis of the upsell A/B test u15.3.1 vs u15.4.1** —
   10 000-iteration bootstrap of the difference of means with one-sided
   95% CI, computed across 11 metrics × 5 segmentation axes
   (subscription, utm_source, geo, payment_method, channel). Headline
   result: Upsell Rate (on View) **+34.29% (p<0.001)**, AOV (on Purchasing
   Users) **−25.50% (p<0.001)**. Notebook:
   [`notebooks/04_ab_test_bootstrap.ipynb`](notebooks/04_ab_test_bootstrap.ipynb).

4. **Sensitivity analysis** — Minimum Detectable Effect (MDE) at 80%
   target power, plus power for given MDE, on both binomial and
   continuous metrics. Implemented with `scipy.stats` and
   `scipy.optimize.brentq`.

5. **Follow-up A/B test design (u15.4.0 vs u15.4.5)** with extended
   tracking of the Insufficient-Funds modal interaction, declined
   payments tagged with `decline_message LIKE 'Insufficient Funds'`, and
   refund-tagged Intercom tickets.
   See [`sql/05_upsell_ab_test_u15_4.sql`](sql/05_upsell_ab_test_u15_4.sql).

## Stack

- **Google BigQuery** (project `hopeful-list-429812-f3`) — partitioned
  tables, kebab-case table names quoted with backticks, JSON_VALUE
  parsing of `event_metadata` / `query_parameters` / `user_metadata`
- **Fivetran** ELT — Facebook Ads, Google Ads, TikTok Ads, Customer.io
- **Payments** — Adyen + Airwallex, unified into
  `payments.all_payments_prod` (amounts in cents, `created_at` in
  microseconds, `rebill_count` encodes upsell order)
- **Python 3.11** — `pandas`, `numpy`, `scipy.stats`, `statsmodels`,
  `google-cloud-bigquery`; Jupyter Notebook for analysis
- **Tableau** — primary BI tool for upsell + retention dashboards
- **Looker Studio** — secondary BI, Custom Query data sources with
  Extract Data caching enabled
- **Git / GitHub** — version control

## Repository layout

```
jobescape-product-analytics/
├── README.md
├── requirements.txt
├── sql/
│   ├── 01_data_exploration.sql            # daily volume, top events, geo split
│   ├── 02_onboarding_funnel.sql           # path → email → subscribe → signup → upsell view
│   ├── 03_retention_cohorts.sql           # D0–D30 retention, Lessons + AI-Tools, with device parser
│   ├── 04_upsell_user_level.sql           # user-level upsell pull (joins funnel + app + payments + intercom)
│   ├── 05_upsell_ab_test_u15_4.sql        # u15.4.0 vs u15.4.5 — current test (with Insufficient-Funds tracking)
│   └── 06_upsell_ab_test_u15_3_vs_u15_4.sql  # u15.3.1 vs u15.4.1 — previous test (input to bootstrap)
├── notebooks/
│   ├── 01_data_cleaning.ipynb
│   ├── 02_metrics_eda.ipynb
│   ├── 03_segmentation.ipynb
│   └── 04_ab_test_bootstrap.ipynb         # 10 000-iter bootstrap + sensitivity analysis
├── dashboards/
│   ├── README.md
│   └── fig0X_*.png                        # 9 Tableau / BigQuery screenshots
├── diagrams/
│   └── README.md
└── docs/
    └── data_dictionary.md
```

## Running locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
gcloud auth application-default login
```

Open any notebook in JupyterLab and replace the `bigquery.Client(project=...)`
call with your own GCP project if you fork this repo.

## Cost safety

This repo runs queries against a **production BigQuery warehouse**.
To prevent accidental large scans:

1. **All notebooks set `maximum_bytes_billed`** — 10 GB for ad-hoc
   exploration, 1 GB for small ab_tests pulls. If a query would scan
   more than the cap, BigQuery returns an error **without charging**.
2. **Default time windows are short** (7–30 days). Do not extend without
   first checking the dry-run estimate in the BigQuery Console.
3. **Every join to `events.*` uses partition predicates**
   (`DATE(timestamp) BETWEEN ...` or `timestamp >= ...`). Do not remove
   these predicates — partition pruning is the difference between
   scanning a few GB and scanning the whole table.
4. **Run SQL files one query at a time.** In the BigQuery Console,
   highlight a single SELECT/WITH statement and click Run — never run
   the whole file at once.
5. **Always read the dry-run estimate** before clicking Run. If estimate
   > 5 GB for a 14-day window — abort and narrow further.

## Disclaimer

This repository contains analysis code and metric definitions only. No
raw user data, payment data, or PII is committed.
