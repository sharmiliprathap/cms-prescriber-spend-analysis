-- National metrics
SELECT
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / NULLIF(SUM(total_claims), 0), 2) AS avg_cost_per_claim
FROM analytics.partd_prescriber_2023_clean;


-- Spend by state
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


-- Spend by prescriber type
SELECT
    prescriber_type,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / SUM(total_claims), 2) AS cost_per_claim
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_type IS NOT NULL
GROUP BY prescriber_type
HAVING SUM(total_claims) > 10000
ORDER BY total_drug_cost DESC;

-- State share of national spend (top 10)
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


-- Prescriber spend concentration (Pareto buckets)
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

-- verify distribution 
SELECT
    COUNT(*) FILTER (WHERE total_drug_cost >= 1000000) AS prescribers_over_1m,
    COUNT(*) FILTER (WHERE total_drug_cost BETWEEN 250000 AND 999999.99) AS prescribers_250k_to_1m,
    COUNT(*) FILTER (WHERE total_drug_cost < 250000 OR total_drug_cost IS NULL) AS prescribers_below_250k
FROM analytics.partd_prescriber_2023_clean;

-- Top 5 prescribers in each state by spend
WITH state_ranked AS (
    SELECT
        prescriber_state,
        prescriber_npi,
        prescriber_type,
        total_claims,
        total_drug_cost,
        ROW_NUMBER() OVER (PARTITION BY prescriber_state ORDER BY total_drug_cost DESC NULLS LAST) AS rn
    FROM analytics.partd_prescriber_2023_clean
    WHERE prescriber_state IS NOT NULL
)
-- Metro vs Suburban vs Rural comparison
SELECT
    prescriber_state,
    prescriber_npi,
    prescriber_type,
    total_claims,
    total_drug_cost
FROM state_ranked
WHERE rn <= 5
ORDER BY prescriber_state, total_drug_cost DESC;

-- State and specialty priority segments
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

-- how many rows fall in each segment.
WITH seg AS (
    SELECT
        CASE
            WHEN SUM(total_drug_cost) >= 1000000 OR SUM(total_claims) >= 50000 THEN 'High Priority'
            WHEN SUM(total_drug_cost) >= 250000 OR SUM(total_claims) >= 15000 THEN 'Watchlist'
            ELSE 'Baseline'
        END AS segment_label
    FROM analytics.partd_prescriber_2023_clean
    WHERE prescriber_state IS NOT NULL
      AND prescriber_type IS NOT NULL
    GROUP BY prescriber_state, prescriber_type
)
SELECT segment_label, COUNT(*) AS segment_count
FROM seg
GROUP BY segment_label
ORDER BY segment_count DESC;

-- Dashboard view: national KPIs
CREATE OR REPLACE VIEW analytics.vw_kpi_national AS
SELECT
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / NULLIF(SUM(total_claims), 0), 2) AS cost_per_claim,
    ROUND(AVG(opioid_claim_share) * 100, 2) AS avg_opioid_share_pct
FROM analytics.partd_prescriber_2023_clean;

-- Dashboard view: state summary
CREATE OR REPLACE VIEW analytics.vw_state_summary AS
SELECT
    prescriber_state,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(SUM(total_drug_cost) / NULLIF(SUM(total_claims), 0), 2) AS cost_per_claim
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_state IS NOT NULL
GROUP BY prescriber_state;

-- Dashboard view: prescriber type summary
CREATE OR REPLACE VIEW analytics.vw_prscrbr_type_summary AS
SELECT
    prescriber_type,
    COUNT(*) AS prescriber_count,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    ROUND(AVG(opioid_claim_share) * 100, 2) AS avg_opioid_share_pct
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_type IS NOT NULL
GROUP BY prescriber_type;

-- Dashboard view: state x prescriber type segments
CREATE OR REPLACE VIEW analytics.vw_state_specialty AS
SELECT
    prescriber_state,
    prescriber_type,
    SUM(total_claims) AS total_claims,
    SUM(total_drug_cost) AS total_drug_cost,
    CASE
        WHEN SUM(total_drug_cost) >= 1000000 OR SUM(total_claims) >= 50000 THEN 'High Priority'
        WHEN SUM(total_drug_cost) >= 250000 OR SUM(total_claims) >= 15000 THEN 'Watchlist'
        ELSE 'Baseline'
    END AS segment_label
FROM analytics.partd_prescriber_2023_clean
WHERE prescriber_state IS NOT NULL
  AND prescriber_type IS NOT NULL
GROUP BY prescriber_state, prescriber_type;
