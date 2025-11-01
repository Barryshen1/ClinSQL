WITH ami_admissions AS (
    -- Step 1: Identify admissions with Acute Myocardial Infarction (AMI)
    -- ICD-10 codes for AMI range from I21.x to I22.x
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE icd_version = 10
      AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%')
),
exclusion_admissions AS (
    -- Step 2: Identify admissions with shock or respiratory failure for exclusion
    -- ICD-10 codes for shock: R57.x (Cardiogenic/Hypovolemic/Other Shock), R65.x (SIRS/Septic Shock), T78.x (Anaphylactic/Allergic Shock)
    -- ICD-10 codes for respiratory failure: J96.x (Acute/Chronic/Unspecified Respiratory Failure)
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
    WHERE icd_version = 10
      AND (icd_code LIKE 'R57%' -- Shock (e.g., R57.0 Cardiogenic shock)
           OR icd_code LIKE 'R65%' -- Systemic Inflammatory Response Syndrome (SIRS), R65.21 (Septic shock)
           OR icd_code LIKE 'T78%' -- Adverse effects, not elsewhere classified (e.g., T78.2 Anaphylactic shock)
           OR icd_code LIKE 'J96%' -- Respiratory failure (e.g., J96.0x Acute respiratory failure)
          )
),
cohort_base AS (
    -- Step 3: Establish the base cohort applying age/gender filters and exclusions
    SELECT
        ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.deathtime,
        ad.hospital_expire_flag,
        p.gender,
        p.anchor_age,
        ad.admission_type,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        CASE
            WHEN ad.admission_type IN ('EW EMER.', 'DIRECT EMER.') THEN 'Emergent'
            ELSE 'Non-Emergent'
        END AS admission_type_grouped,
        CASE
            WHEN ad.hospital_expire_flag = 1 AND ad.deathtime IS NOT NULL THEN DATE_DIFF(ad.deathtime, ad.admittime, DAY)
            ELSE NULL
        END AS time_to_death_days_if_died
    FROM
        `physionet-data.mimiciv_3_1_hosp`.admissions ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp`.patients p
        ON ad.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 66 AND 76
        AND ad.hadm_id IN (SELECT hadm_id FROM ami_admissions)
        AND ad.hadm_id NOT IN (SELECT hadm_id FROM exclusion_admissions)
),
cohort_categorized AS (
    -- Step 4: Categorize the cohort by Length of Stay (LOS)
    SELECT
        *,
        CASE
            WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
            WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
            WHEN los_days >= 8 THEN '>=8 days'
            ELSE 'Unknown/Invalid LOS' -- Should not occur with valid data but added for robustness
        END AS los_category
    FROM
        cohort_base
    WHERE los_days IS NOT NULL AND los_days >= 0 -- Exclude admissions with invalid or negative LOS
)
-- Step 5: Aggregate and calculate final metrics
SELECT
    los_category,
    admission_type_grouped,
    COUNT(hadm_id) AS num_admissions,
    SUM(hospital_expire_flag) AS in_hospital_deaths,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(hadm_id), 2) AS mortality_rate_percent,
    -- CORRECTED: Replaced PERCENTILE_CONT with APPROX_QUANTILES for median calculation
    APPROX_QUANTILES(time_to_death_days_if_died, 2)[OFFSET(1)] AS median_time_to_death_days
FROM
    cohort_categorized
WHERE los_category <> 'Unknown/Invalid LOS'
GROUP BY
    los_category,
    admission_type_grouped
ORDER BY
    -- Custom order for LOS categories
    CASE los_category
        WHEN '1-3 days' THEN 1
        WHEN '4-7 days' THEN 2
        WHEN '>=8 days' THEN 3
        ELSE 4
    END,
    admission_type_grouped;