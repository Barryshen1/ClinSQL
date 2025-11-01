WITH cohort_ich_admissions AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag,
        pat.gender,
        pat.anchor_age,
        pat.dod -- Date of death from patients table for 30-day mortality
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON ad.subject_id = pat.subject_id
    WHERE
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 69 AND 79
        AND EXISTS ( -- Check for ICH diagnosis
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE
                di.hadm_id = ad.hadm_id
                AND (
                    -- ICD-9 codes for ICH: 430 (Subarachnoid hemorrhage), 431 (Intracerebral hemorrhage), 432 (Other/unspecified intracranial hemorrhage)
                    (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432'))
                    OR
                    -- ICD-10 codes for ICH: I60 (Nontraumatic subarachnoid hemorrhage), I61 (Nontraumatic intracerebral hemorrhage), I62 (Other nontraumatic intracranial hemorrhage)
                    (di.icd_version = 10 AND di.icd_code IN ('I60', 'I61', 'I62'))
                )
        )
),
-- Calculate a proxy composite_risk_score (number of unique diagnoses per admission)
admission_risk_score AS (
    SELECT
        di.hadm_id,
        COUNT(DISTINCT di.icd_code) AS composite_risk_score_proxy -- Using count of unique ICD codes as a proxy for risk score
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    GROUP BY
        di.hadm_id
),
-- Define Major Complication (presence of Sepsis diagnosis)
admission_major_complication AS (
    SELECT
        di.hadm_id,
        MAX(CASE
            WHEN
                (di.icd_version = 9 AND di.icd_code LIKE '038%') -- ICD-9 for Sepsis
                OR
                (di.icd_version = 10 AND (di.icd_code LIKE 'A40%' OR di.icd_code LIKE 'A41%')) -- ICD-10 for Sepsis
            THEN 1
            ELSE 0
        END) AS has_major_complication
    FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    GROUP BY
        di.hadm_id
),
-- Combine cohort data with risk score, complication, and calculate mortality/LOS flags
admission_details AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.admittime,
        c.dischtime,
        c.hospital_expire_flag,
        c.dod,
        COALESCE(ars.composite_risk_score_proxy, 0) AS composite_risk_score, -- Use 0 if no diagnoses found (unlikely for an admission in cohort)
        COALESCE(amc.has_major_complication, 0) AS has_major_complication_flag,
        -- Calculate 30-day mortality flag (death within 30 days of admission)
        CASE
            WHEN c.dod IS NOT NULL
                 -- Ensure death occurred on or after admission date
                 AND CAST(c.dod AS DATE) >= CAST(c.admittime AS DATE)
                 AND DATE_DIFF(CAST(c.dod AS DATE), CAST(c.admittime AS DATE), DAY) <= 30
            THEN 1
            ELSE 0
        END AS is_30_day_mortality,
        -- Calculate Length of Stay in days
        DATE_DIFF(CAST(c.dischtime AS DATE), CAST(c.admittime AS DATE), DAY) AS los_days
    FROM
        cohort_ich_admissions AS c
    LEFT JOIN
        admission_risk_score AS ars
        ON c.hadm_id = ars.hadm_id
    LEFT JOIN
        admission_major_complication AS amc
        ON c.hadm_id = amc.hadm_id
),
-- Assign quintiles based on the composite_risk_score and filter for valid LOS
ranked_admissions AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY composite_risk_score ASC) AS risk_quintile -- Lower score = lower quintile
    FROM
        admission_details
    WHERE
        los_days IS NOT NULL AND los_days >= 0 -- Ensure positive LOS for meaningful calculations
)
-- Final aggregation per quintile
SELECT
    risk_quintile,
    COUNT(hadm_id) AS n_admissions,
    AVG(is_30_day_mortality) * 100 AS percent_30_day_mortality,
    AVG(has_major_complication_flag) * 100 AS percent_major_complication,
    -- Calculate median LOS for survivors (is_30_day_mortality = 0) within each quintile
    APPROX_QUANTILES(
        CASE WHEN is_30_day_mortality = 0 THEN los_days ELSE NULL END,
        2
    )[OFFSET(1)] AS median_survivor_los
FROM
    ranked_admissions
GROUP BY
    risk_quintile
ORDER BY
    risk_quintile;