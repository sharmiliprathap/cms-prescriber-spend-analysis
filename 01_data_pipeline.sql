
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS raw.partd_prescriber_2023_stg;
CREATE TABLE raw.partd_prescriber_2023_stg (
    PRSCRBR_NPI TEXT,
    Prscrbr_Last_Org_Name TEXT,
    Prscrbr_First_Name TEXT,
    Prscrbr_MI TEXT,
    Prscrbr_Crdntls TEXT,
    Prscrbr_Ent_Cd TEXT,
    Prscrbr_St1 TEXT,
    Prscrbr_St2 TEXT,
    Prscrbr_City TEXT,
    Prscrbr_State_Abrvtn TEXT,
    Prscrbr_State_FIPS TEXT,
    Prscrbr_zip5 TEXT,
    Prscrbr_RUCA TEXT,
    Prscrbr_RUCA_Desc TEXT,
    Prscrbr_Cntry TEXT,
    Prscrbr_Type TEXT,
    Prscrbr_Type_src TEXT,
    Tot_Clms TEXT,
    Tot_30day_Fills TEXT,
    Tot_Drug_Cst TEXT,
    Tot_Day_Suply TEXT,
    Tot_Benes TEXT,
    GE65_Sprsn_Flag TEXT,
    GE65_Tot_Clms TEXT,
    GE65_Tot_30day_Fills TEXT,
    GE65_Tot_Drug_Cst TEXT,
    GE65_Tot_Day_Suply TEXT,
    GE65_Bene_Sprsn_Flag TEXT,
    GE65_Tot_Benes TEXT,
    Brnd_Sprsn_Flag TEXT,
    Brnd_Tot_Clms TEXT,
    Brnd_Tot_Drug_Cst TEXT,
    Gnrc_Sprsn_Flag TEXT,
    Gnrc_Tot_Clms TEXT,
    Gnrc_Tot_Drug_Cst TEXT,
    Othr_Sprsn_Flag TEXT,
    Othr_Tot_Clms TEXT,
    Othr_Tot_Drug_Cst TEXT,
    MAPD_Sprsn_Flag TEXT,
    MAPD_Tot_Clms TEXT,
    MAPD_Tot_Drug_Cst TEXT,
    PDP_Sprsn_Flag TEXT,
    PDP_Tot_Clms TEXT,
    PDP_Tot_Drug_Cst TEXT,
    LIS_Sprsn_Flag TEXT,
    LIS_Tot_Clms TEXT,
    LIS_Drug_Cst TEXT,
    NonLIS_Sprsn_Flag TEXT,
    NonLIS_Tot_Clms TEXT,
    NonLIS_Drug_Cst TEXT,
    Opioid_Tot_Clms TEXT,
    Opioid_Tot_Drug_Cst TEXT,
    Opioid_Tot_Suply TEXT,
    Opioid_Tot_Benes TEXT,
    Opioid_Prscrbr_Rate TEXT,
    Opioid_LA_Tot_Clms TEXT,
    Opioid_LA_Tot_Drug_Cst TEXT,
    Opioid_LA_Tot_Suply TEXT,
    Opioid_LA_Tot_Benes TEXT,
    Opioid_LA_Prscrbr_Rate TEXT,
    Antbtc_Tot_Clms TEXT,
    Antbtc_Tot_Drug_Cst TEXT,
    Antbtc_Tot_Benes TEXT,
    Antpsyct_GE65_Sprsn_Flag TEXT,
    Antpsyct_GE65_Tot_Clms TEXT,
    Antpsyct_GE65_Tot_Drug_Cst TEXT,
    Antpsyct_GE65_Bene_Suprsn_Flag TEXT,
    Antpsyct_GE65_Tot_Benes TEXT,
    Bene_Avg_Age TEXT,
    Bene_Age_LT_65_Cnt TEXT,
    Bene_Age_65_74_Cnt TEXT,
    Bene_Age_75_84_Cnt TEXT,
    Bene_Age_GT_84_Cnt TEXT,
    Bene_Feml_Cnt TEXT,
    Bene_Male_Cnt TEXT,
    Bene_Race_Wht_Cnt TEXT,
    Bene_Race_Black_Cnt TEXT,
    Bene_Race_Api_Cnt TEXT,
    Bene_Race_Hspnc_Cnt TEXT,
    Bene_Race_Natind_Cnt TEXT,
    Bene_Race_Othr_Cnt TEXT,
    Bene_Dual_Cnt TEXT,
    Bene_Ndual_Cnt TEXT,
    Bene_Avg_Risk_Scre TEXT
);

TRUNCATE TABLE raw.partd_prescriber_2023_stg;
COPY raw.partd_prescriber_2023_stg
FROM '/private/tmp/MUP_DPR_RY25_P04_V10_DY23_NPI.csv'
DELIMITER ',' CSV HEADER;

-- confirm state values before fixing placeholders
SELECT Prscrbr_State_Abrvtn, COUNT(*) AS row_count
FROM raw.partd_prescriber_2023_stg
GROUP BY Prscrbr_State_Abrvtn
ORDER BY row_count DESC
LIMIT 20;

DROP TABLE IF EXISTS analytics.partd_prescriber_2023_clean;
CREATE TABLE analytics.partd_prescriber_2023_clean (
    report_year INTEGER NOT NULL,
    prescriber_npi BIGINT NOT NULL,
    prescriber_state TEXT,
    prescriber_city TEXT,
    prescriber_type TEXT,
    prescriber_ruca INTEGER,
    total_claims INTEGER,
    total_drug_cost NUMERIC(18,2),
    total_beneficiaries INTEGER,
    opioid_claims INTEGER,
    antibiotic_claims INTEGER,
    beneficiary_avg_risk_score NUMERIC(18,6),
    ge65_suppressed BOOLEAN,
    brand_suppressed BOOLEAN,
    generic_suppressed BOOLEAN,
    cost_per_claim NUMERIC(18,4),
    opioid_claim_share NUMERIC(18,6),
    antibiotic_claim_share NUMERIC(18,6),
    created_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (report_year, prescriber_npi)
);

INSERT INTO analytics.partd_prescriber_2023_clean (
    report_year,
    prescriber_npi,
    prescriber_state,
    prescriber_city,
    prescriber_type,
    prescriber_ruca,
    total_claims,
    total_drug_cost,
    total_beneficiaries,
    opioid_claims,
    antibiotic_claims,
    beneficiary_avg_risk_score,
    ge65_suppressed,
    brand_suppressed,
    generic_suppressed
)
SELECT
    2023,

    BTRIM(PRSCRBR_NPI)::BIGINT,

    CASE
        WHEN BTRIM(Prscrbr_State_Abrvtn) IN ('', 'XX') THEN NULL
        ELSE UPPER(BTRIM(Prscrbr_State_Abrvtn))
    END,

    NULLIF(INITCAP(BTRIM(Prscrbr_City)), ''),

    NULLIF(INITCAP(BTRIM(Prscrbr_Type)), ''),

    CASE
        WHEN BTRIM(Prscrbr_RUCA) IN ('', '*', '#') THEN NULL
        ELSE ROUND(BTRIM(Prscrbr_RUCA)::NUMERIC)::INTEGER
    END,

    CASE
        WHEN BTRIM(Tot_Clms) IN ('', '*', '#') THEN NULL
        ELSE ROUND(BTRIM(Tot_Clms)::NUMERIC)::INTEGER
    END,

    CASE
        WHEN BTRIM(Tot_Drug_Cst) IN ('', '*', '#') THEN NULL
        ELSE BTRIM(Tot_Drug_Cst)::NUMERIC(18,2)
    END,

    CASE
        WHEN BTRIM(Tot_Benes) IN ('', '*', '#') THEN NULL
        ELSE ROUND(BTRIM(Tot_Benes)::NUMERIC)::INTEGER
    END,

    CASE
        WHEN BTRIM(Opioid_Tot_Clms) IN ('', '*', '#') THEN NULL
        ELSE ROUND(BTRIM(Opioid_Tot_Clms)::NUMERIC)::INTEGER
    END,

    CASE
        WHEN BTRIM(Antbtc_Tot_Clms) IN ('', '*', '#') THEN NULL
        ELSE ROUND(BTRIM(Antbtc_Tot_Clms)::NUMERIC)::INTEGER
    END,

    CASE
        WHEN BTRIM(Bene_Avg_Risk_Scre) IN ('', '*', '#') THEN NULL
        ELSE BTRIM(Bene_Avg_Risk_Scre)::NUMERIC(18,6)
    END,

    GE65_Sprsn_Flag = '*',
    Brnd_Sprsn_Flag = '*',
    Gnrc_Sprsn_Flag = '*'

FROM raw.partd_prescriber_2023_stg
WHERE BTRIM(PRSCRBR_NPI) <> '';

UPDATE analytics.partd_prescriber_2023_clean
SET total_claims = NULL
WHERE total_claims < 0;

UPDATE analytics.partd_prescriber_2023_clean
SET total_drug_cost = NULL
WHERE total_drug_cost < 0;

UPDATE analytics.partd_prescriber_2023_clean
SET
    cost_per_claim = CASE WHEN total_claims > 0 THEN total_drug_cost / total_claims ELSE NULL END,
    opioid_claim_share = CASE WHEN total_claims > 0 THEN opioid_claims::NUMERIC / total_claims ELSE NULL END,
    antibiotic_claim_share = CASE WHEN total_claims > 0 THEN antibiotic_claims::NUMERIC / total_claims ELSE NULL END;

CREATE INDEX IF NOT EXISTS idx_partd_2023_state ON analytics.partd_prescriber_2023_clean (prescriber_state);
CREATE INDEX IF NOT EXISTS idx_partd_2023_type ON analytics.partd_prescriber_2023_clean (prescriber_type);
CREATE INDEX IF NOT EXISTS idx_partd_2023_cost ON analytics.partd_prescriber_2023_clean (total_drug_cost);

-- how many raw rows were skipped because NPI was invalid
SELECT
    (SELECT COUNT(*) 
     FROM raw.partd_prescriber_2023_stg) AS raw_rows,
    (SELECT COUNT(*) 
     FROM raw.partd_prescriber_2023_stg 
     WHERE BTRIM(PRSCRBR_NPI) ~ '^[0-9]+$') AS rows_with_valid_npi,
    (SELECT COUNT(*) 
     FROM analytics.partd_prescriber_2023_clean) AS clean_rows;

SELECT report_year, prescriber_npi, COUNT(*) AS row_count
FROM analytics.partd_prescriber_2023_clean
GROUP BY report_year, prescriber_npi
HAVING COUNT(*) > 1;
