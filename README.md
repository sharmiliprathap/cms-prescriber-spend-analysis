# Healthcare Payment Concentration and Prescribing Patterns (CMS Part D 2023)

## Introduction
This project analyzes U.S. Medicare Part D prescriber-level data to understand where drug spending is concentrated and which state-specialty segments carry the highest operational priority. The core goal is to move from raw records to decision-ready findings using SQL-first analysis on a 1M+ row dataset. This project focuses on concentration patterns by geography, specialty, and prescriber tiers to help prioritize actions where financial exposure is highest.
## Dataset
This analysis uses the CMS Medicare Part D Prescribers by Provider public file (2023).

- **Dataset name:** Medicare Part D Prescribers by Provider (NPI level)
- **Year used:** 2023
- **Scale used in this project:** 1,380,665 prescriber rows
- **Primary file used:** [MUP_DPR_RY25_P04_V10_DY23_NPI.csv](https://catalog.data.gov/dataset/medicare-part-d-prescribers-by-provider-a2fc0)

## Tools Used
- PostgreSQL (SQL development and query design)
- Python (pandas) for local execution and quantified result extraction
- Jupyter/VS Code for workflow execution

## Analysis
### 1) National Utilization and Spend 
To begin with, I wanted to establish a national baseline by measuring total prescribers, total claims, total spend, and average cost per claim.

```sql
SELECT
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / SUM(total_claims), 2) AS avg_cost_per_claim
FROM analytics.partd_prescriber_2023_clean;
```
The dataset contains **1,380,665 prescribers**, **1,615,685,370 total claims**, and **$275,647,552,066.21 total drug cost**. The national average cost per claim is **$170.61**, confirming very large-scale spend concentration potential.

### 2) State-Level Spend Concentration
To identify where cost concentration is the highest, I ranked states by total spend and utilization.

```sql
SELECT
    prescriber_state,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / SUM(total_claims), 2) AS cost_per_claim,
    ROUND(AVG(opioid_claim_share) * 100, 2) AS avg_opioid_share_pct
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_state IS NOT NULL
GROUP BY prescriber_state
ORDER BY total_drug_cost DESC;
```
Top 5 states by spend are **CA ($27.10B)**, **NY ($22.46B)**, **FL ($20.29B)**, **TX ($19.28B)**, and **PA ($13.21B)**. Together, these 5 states contribute **37.13%** of total spend; top 10 states contribute **54.50%**.

### 3) Specialty-Level Spend Concentration
To identify specialties driving the largest total drug spend and usage volume, I aggregated total claims and total drug cost by prescriber type.

```sql
SELECT
    prescriber_type,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / NULLIF(SUM(total_claims), 0), 2) AS cost_per_claim
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_type IS NOT NULL
GROUP BY prescriber_type
HAVING SUM(total_claims) > 10000
ORDER BY total_drug_cost DESC;
```
Top specialties by spend are **Nurse Practitioner ($45.57B)**, **Internal Medicine ($43.77B)**, **Family Practice ($39.47B)**, **Hematology-Oncology ($18.78B)**, and **Physician Assistant ($16.88B)**. These top 5 specialties explain **59.67%** of specialty-level spend.

### 4) State Share of National Spend
To calculate each state’s percentage contribution to national spend, I summed total drug cost by state and divided each state total by the national total.
```sql
WITH state_spend AS (
    SELECT prescriber_state, 
           SUM(total_drug_cost) AS state_total_cost
    FROM analytics.partd_prescriber_2023_clean
    WHERE prescriber_state IS NOT NULL
    GROUP BY prescriber_state
)
SELECT
    prescriber_state,
    state_total_cost,
    ROUND(100.0 * state_total_cost / SUM(state_total_cost) OVER (), 2) AS state_cost_share_pct
FROM state_spend
ORDER BY state_total_cost DESC
LIMIT 10;
```
Spend is not evenly distributed across the U.S. The top 10 states alone account for **54.50%** of total drug spend, showing high geographic concentration.

### 5) Prescriber-Level Pareto Concentration
To measure how much spend is concentrated in top prescriber percentiles, I ranked prescribers by total drug cost and calculated spend share across percentile buckets.

```sql
WITH ranked AS (
    SELECT
        prescriber_npi,
        total_drug_cost,
        NTILE(100) OVER (ORDER BY total_drug_cost DESC NULLS LAST) AS spend_percentile
    FROM analytics.partd_prescriber_2023_clean
)
SELECT
    CASE
        WHEN spend_percentile <= 1 THEN 'Top 1%'
        WHEN spend_percentile <= 5 THEN 'Top 5%'
        WHEN spend_percentile <= 10 THEN 'Top 10%'
        ELSE 'Remaining 90%'
    END AS segment,
    SUM(total_drug_cost) AS segment_total_cost,
    ROUND(100.0 * SUM(total_drug_cost) / SUM(SUM(total_drug_cost)) OVER (), 2) AS segment_share_pct
FROM ranked
GROUP BY 1
ORDER BY segment_total_cost DESC;
```
Spend is heavily concentrated: **Top 1% contributes 22.10%** of total spend, and cumulative **Top 10% contributes about 70.08%**. This confirms a strong Pareto pattern.

### 6) Metro vs Suburban vs Rural Spend Pattern
To compare spend and cost per claim across RUCA area types, I grouped prescribers into metro, suburban, rural, and unknown categories and aggregated claims and drug cost for each group.

```sql
SELECT
    CASE
        WHEN prescriber_ruca IN (1, 2, 3) THEN 'Metro'
        WHEN prescriber_ruca BETWEEN 4 AND 6 THEN 'Suburban'
        WHEN prescriber_ruca BETWEEN 7 AND 10 THEN 'Rural'
        ELSE 'Unknown'
    END AS area_type,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / SUM(total_claims), 2) AS cost_per_claim
FROM analytics.partd_prescriber_2023_clean
GROUP BY 1
ORDER BY total_drug_cost DESC;
```
**Metro** accounts for **$237.56B** with **$180.94** cost per claim, compared to **Suburban $21.78B ($135.18)** and **Rural $11.93B ($105.41)**. Metro areas show the highest financial concentration and higher unit cost.

### 7) State-Specialty Priority Segmentation (Threshold-Based)
To create business-friendly segments using practical thresholds rather than abstract scoring, I classified each state-specialty group into High Priority, Watchlist, or Baseline based on total claims and total drug cost cutoffs.

```sql
SELECT
    prescriber_state,
    prescriber_type,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(AVG(opioid_claim_share) * 100, 2) AS opioid_share_pct,
    CASE
        WHEN SUM(total_drug_cost) >= 1000000 OR SUM(total_claims) >= 50000 THEN 'High Priority'
        WHEN SUM(total_drug_cost) >= 250000 OR SUM(total_claims) >= 15000 THEN 'Watchlist'
        ELSE 'Baseline'
    END AS segment_label
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_state IS NOT NULL
  AND prescriber_type IS NOT NULL
GROUP BY prescriber_state, prescriber_type
ORDER BY total_drug_cost DESC;
```
Across **5,288 state-specialty segments**, the model labels **2,538 High Priority**, **655 Watchlist**, and **2,095 Baseline**. Largest spend clusters include **CA-Internal Medicine ($5.52B)** and **NY-Internal Medicine ($4.69B)**.

## Conclusion
The results show that Medicare Part D spend in 2023 is highly concentrated by prescriber tier, state, and specialty. Out of **$275.65B** total spend, about **70.08%** is concentrated in the top 10% prescriber tier, while the top 10 states account for **54.50%** and top 5 specialties account for **59.67%**. This concentration pattern provides a clear action path which is to prioritize high-exposure state-specialty clusters first and then drill down to top prescribers within those clusters for targeted monitoring and planning.

## Limitations
- Analysis is based on one year (2023); no year-over-year trend here.
- Suppressed values (`*`, `#`) are treated as missing, which may slightly understate some subgroup totals.
- Segment labels use fixed thresholds for business usability; thresholds can be tuned for different policy or operational goals.
- Results reflect aggregate pattern detection, not causal or clinical judgment.
