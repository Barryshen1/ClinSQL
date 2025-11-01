WITH
-- Step 1: Identify all hospital admissions with a primary diagnosis of Acute Myocardial Infarction (AMI)
ami_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for AMI
        (icd_version = 9 AND STARTS_WITH(icd_code, '410'))
        OR
        -- ICD-10 codes for AMI
        (icd_version = 10 AND (STARTS_WITH(icd_code, 'I21') OR STARTS_WITH(icd_code, 'I22')))
),

-- Step 2: Identify all hospital admissions with diagnoses for exclusion (shock or respiratory failure)
exclusion_diagnoses AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        -- ICD-9 codes for shock and respiratory failure
        (icd_version = 9 AND (
            STARTS_WITH(icd_code, '7855') -- Shock
            OR STARTS_WITH(icd_code, '5188')    -- Acute respiratory failure
        ))
        OR
        -- ICD-10 codes for shock and respiratory failure
        (icd_version = 10 AND (
            STARTS_WITH(icd_code, 'R57') -- Shock
            OR STARTS_WITH(icd_code, 'J96')     -- Respiratory failure
        ))
),

-- Step 3: Build the final cohort with all required attributes for analysis
cohort AS (
    SELECT
        adm.hadm_id,
        adm.hospital_expire_flag,
        -- Calculate hospital length of stay in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los_days,
        -- Flag if the patient was admitted to an ICU within the first day of hospitalization
        (EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
            WHERE icu.hadm_id = adm.hadm_id
              AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
        )) AS was_in_icu_day_1
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Filter for male patients aged 40-50
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
        ON adm.subject_id = pat.subject_id
        AND pat.gender = 'M'
        AND pat.anchor_age >= 40 AND pat.anchor_age <= 50
    -- Must have an AMI diagnosis
    INNER JOIN ami_admissions AS ami
        ON adm.hadm_id = ami.hadm_id
    -- Must NOT have a shock or respiratory failure diagnosis
    LEFT JOIN exclusion_diagnoses AS ex
        ON adm.hadm_id = ex.hadm_id
    WHERE ex.hadm_id IS NULL -- This join condition performs the exclusion
)

-- Step 4: Aggregate the cohort data to produce the final report
SELECT
    CASE
        WHEN was_in_icu_day_1 THEN 'In ICU on Day 1'
        ELSE 'Not in ICU on Day 1'
    END AS day_1_icu_status,
    CASE
        WHEN hospital_los_days <= 5 THEN 'LOS <= 5 days'
        ELSE 'LOS > 5 days'
    END AS los_group,
    COUNT(hadm_id) AS number_of_admissions,
    -- Calculate in-hospital mortality percentage by averaging the 0/1 flag
    ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
    -- Calculate the median hospital LOS for each group
    APPROX_QUANTILES(hospital_los_days, 100)[OFFSET(50)] AS median_hospital_los_days
FROM cohort
-- Ensure LOS is calculable (dischtime is not null)
WHERE hospital_los_days IS NOT NULL
GROUP BY
    day_1_icu_status,
    los_group
ORDER BY
    day_1_icu_status DESC,
    los_group;