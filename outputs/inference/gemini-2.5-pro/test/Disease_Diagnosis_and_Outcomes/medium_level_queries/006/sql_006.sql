WITH
-- CTE 1: Identify all hospital admissions with a diagnosis of sepsis
sepsis_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Sepsis (ICD-9), Other sepsis (ICD-10), Severe sepsis w/o septic shock (ICD-10)
        icd_code IN ('99591', 'R6520') OR icd_code LIKE 'A41%'
),

-- CTE 2: Identify all hospital admissions with a diagnosis of septic shock
septic_shock_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- Septic shock (ICD-9), Severe sepsis with septic shock (ICD-10)
        icd_code IN ('78552', 'R6521')
),

-- CTE 3: Identify comorbidities (CKD and Diabetes) for each hospital admission
comorbidities AS (
    SELECT
        hadm_id,
        MAX(CASE
            WHEN icd_version = 9 AND icd_code LIKE '585%' THEN 1
            WHEN icd_version = 10 AND icd_code LIKE 'N18%' THEN 1
            ELSE 0
        END) AS has_ckd,
        MAX(CASE
            WHEN icd_version = 9 AND icd_code LIKE '250%' THEN 1
            WHEN icd_version = 10 AND (
                icd_code LIKE 'E08%' OR
                icd_code LIKE 'E09%' OR
                icd_code LIKE 'E10%' OR
                icd_code LIKE 'E11%' OR
                icd_code LIKE 'E13%'
            ) THEN 1
            ELSE 0
        END) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),

-- CTE 4: Build the primary cohort of patients with LOS and comorbidity flags
cohort_base AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Calculate LOS in fractional days for more precise ranking
        DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days,
        COALESCE(com.has_ckd, 0) AS has_ckd,
        COALESCE(com.has_diabetes, 0) AS has_diabetes
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
    -- Restrict to admissions with a sepsis diagnosis
    INNER JOIN sepsis_admissions AS s
        ON adm.hadm_id = s.hadm_id
    -- Exclude admissions with a septic shock diagnosis
    LEFT JOIN septic_shock_admissions AS ss
        ON adm.hadm_id = ss.hadm_id
    -- Bring in comorbidity flags
    LEFT JOIN comorbidities AS com
        ON adm.hadm_id = com.hadm_id
    WHERE
        pat.gender = 'M'
        AND pat.anchor_age BETWEEN 64 AND 74
        AND ss.hadm_id IS NULL
        -- Ensure LOS can be calculated and is non-negative
        AND adm.dischtime IS NOT NULL AND adm.dischtime >= adm.admittime
),

-- CTE 5: Assign LOS quartiles to the cohort
quartiled_cohort AS (
    SELECT
        *,
        NTILE(4) OVER (ORDER BY los_days) AS los_quartile
    FROM cohort_base
)

-- Final step: Aggregate results by quartile and calculate metrics
SELECT
    los_quartile,
    COUNT(hadm_id) AS number_of_admissions,
    -- Using AVG on a 0/1 flag is a clean way to get a percentage
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent,
    AVG(has_ckd) * 100 AS ckd_prevalence_percent,
    AVG(has_diabetes) * 100 AS diabetes_prevalence_percent
FROM quartiled_cohort
GROUP BY los_quartile
ORDER BY los_quartile;