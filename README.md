# Jobescape — Product Analytics Internship

Industrial internship deliverables — Big Data Analysis, Astana IT University.

- **Student:** Yelnur Zekenov (BDA-2305, ID 230539)
- **Company:** Nomad Ventures Ltd. (product: Jobescape)
- **Department:** Product Analytics
- **Workplace supervisor:** Mirlan Tuleugaliev, Data Analyst
- **Academic supervisor:** Adilet Duman, Astana IT University
- **Period:** 9 March 2026 — 2 May 2026

## Stack

- Google BigQuery (project `hopeful-list-429812-f3`) — data warehouse, partitioned tables, JSON columns
- Fivetran — ELT for Facebook Ads, Google Ads, TikTok Ads, Customer.io
- Adyen / Airwallex — payment data
- Python 3.11 — `pandas`, `numpy`, `scipy.stats`, `statsmodels`, `google-cloud-bigquery`
- Looker Studio — BI dashboards on top of BigQuery
- Jupyter — exploratory analysis and A/B-test write-ups

## Repository layout

```
jobescape-product-analytics/
├── README.md
├── requirements.txt
├── sql/
│   ├── 01_data_exploration.sql
│   ├── 02_onboarding_funnel.sql
│   ├── 03_retention_cohorts.sql
│   ├── 04_upsell_by_segment.sql
│   └── 05_ab_test_pull.sql
├── notebooks/
│   ├── 01_data_cleaning.ipynb
│   ├── 02_metrics_eda.ipynb
│   ├── 03_segmentation.ipynb
│   └── 04_ab_test_significance.ipynb
├── diagrams/
│   ├── data_pipeline.png
│   └── data_model_erd.png
├── dashboards/
│   └── README.md
└── docs/
    └── data_dictionary.md
```

## What's inside

| Area | File | Summary |
|------|------|---------|
| Core metrics | [`sql/03_retention_cohorts.sql`](sql/03_retention_cohorts.sql) | D1/D3/D5/D7 retention cohorts by install date |
| Onboarding | [`sql/02_onboarding_funnel.sql`](sql/02_onboarding_funnel.sql) | Step-by-step onboarding funnel conversion |
| Acquisition | [`sql/04_upsell_by_segment.sql`](sql/04_upsell_by_segment.sql) | Upsell Gain / ARPU by creative & funnel segment |
| Experiments | [`notebooks/04_ab_test_significance.ipynb`](notebooks/04_ab_test_significance.ipynb) | Two-proportion z-test for the paywall A/B |
| Definitions | [`docs/data_dictionary.md`](docs/data_dictionary.md) | Canonical metric definitions used in this work |

## Running locally

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
gcloud auth application-default login
```

Open any notebook in JupyterLab and replace the `bigquery.Client(project=...)` call with your own GCP project if you fork this repo.

## Cost safety

This repo runs queries against a **production BigQuery warehouse**. To prevent accidental large scans:

1. **All notebooks set `maximum_bytes_billed = 10 GB`** (1 GB for the A/B notebook). If a query would scan more than the cap, BigQuery returns an error **without charging**.
2. **Default time windows are short** (7–14 days). Do not extend without first checking the dry-run estimate in the BigQuery Console.
3. **All queries on `events.app-raw-table` use partition predicates** (`DATE(timestamp) BETWEEN ...` or `timestamp >= ...`). Do not remove these predicates — partition pruning is the difference between scanning a few GB and scanning the whole table.
4. **Run SQL files one query at a time.** In the BigQuery Console, highlight a single SELECT/WITH statement and click **Run** — never run the whole file at once.
5. **Always read the dry-run estimate** (top-right of the Query editor: "This query will process N MB / GB") **before clicking Run.** If estimate > 5 GB for a 14-day window — abort and narrow further.

## Disclaimer

This repository contains analysis code and metric definitions only. No raw user data, payment data, or PII is committed.

## Repository

https://github.com/Yelnur-Zeken/jobescape-product-analytics All sample outputs in notebooks are aggregated and anonymized.
