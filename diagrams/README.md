# Diagrams

Architecture and data-flow diagrams used in the final report.

```
+---------------------+      +-----------------------+      +-----------------------------+
| Mobile app          |      | Marketing platforms   |      | Payment processors          |
| iOS / Android       |      | FB / Google / TikTok  |      | Adyen / Airwallex           |
+----------+----------+      +-----------+-----------+      +--------------+--------------+
           |                             |                                 |
           v                             v                                 v
+---------------------+      +-----------------------+      +-----------------------------+
| Backend ingestion   |      | Fivetran ELT          |      | Direct ingestion            |
+----------+----------+      +-----------+-----------+      +--------------+--------------+
           |                             |                                 |
           +------------------+----------+------------------+--------------+
                              |
                              v
                +------------------------------+
                | Google BigQuery              |
                |  - events.app_raw_table      |
                |  - ab_tests.*                |
                |  - facebook_ads.*            |
                |  - payments.*                |
                |  - analytics_draft.*         |
                +-------+----------------------+
                        |
            +-----------+-----------+
            v                       v
+-----------------------+  +------------------------+
| Looker Studio         |  | Python notebooks       |
| dashboards            |  | A/B-test analysis      |
+-----------------------+  +------------------------+
```

Drop the rendered PNG versions of the diagrams here:
- `data_pipeline.png`
- `data_model_erd.png`
