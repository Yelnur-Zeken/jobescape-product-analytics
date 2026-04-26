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

## Disclaimer

This repository contains analysis code and metric definitions only. No raw user data, payment data, or PII is committed.

## Repository

https://github.com/Yelnur-Zeken/jobescape-product-analytics All sample outputs in notebooks are aggregated and anonymized.
