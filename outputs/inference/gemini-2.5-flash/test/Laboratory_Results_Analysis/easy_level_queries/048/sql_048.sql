WITH COPD_Cohort AS (
    -- Step 1: Identify hospitalized women aged 56 with a COPD diagnosis
    SELECT DISTINCT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age = 56 -- Age at first admission or death, as common in MIMIC-IV for cohort selection
        AND (
            (di.icd_version = 9 AND (di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code = '496'))
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
        )
),
Admissions_Avg_Creatinine AS (
    -- Step 2: Calculate the average serum creatinine for each admission in the cohort within the first 24 hours
    SELECT
        cc.subject_id,
        cc.hadm_id,
        AVG(le.valuenum) AS avg_creatinine_24h
    FROM
        COPD_Cohort AS cc
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
        ON cc.subject_id = le.subject_id
        AND cc.hadm_id = le.hadm_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
        ON le.itemid = dli.itemid
    WHERE
        dli.label = 'Creatinine, Serum' -- Specific item for serum creatinine
        AND le.valuenum IS NOT NULL -- Exclude null values for calculation
        AND le.charttime >= cc.admittime
        AND le.charttime <= TIMESTAMP_ADD(cc.admittime, INTERVAL 24 HOUR) -- Measurements within the first 24 hours
    GROUP BY
        cc.subject_id,
        cc.hadm_id
    HAVING
        COUNT(le.valuenum) > 0 -- Ensure at least one valid creatinine measurement in 24h
)
-- Step 3: Calculate the 75th percentile of these average serum creatinine values
SELECT
    PERCENTILE_CONT(avg_creatinine_24h, 0.75) AS p75_avg_creatinine_24h
FROM
    Admissions_Avg_Creatinine;