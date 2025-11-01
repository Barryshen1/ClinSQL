WITH sepsis_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
),
septic_shock_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code = 'R6521' -- ICD-10 code for Septic Shock
),
-- Combine to get eligible sepsis admissions (excluding septic shock)
eligible_admissions AS (
  SELECT hadm_id
  FROM sepsis_admissions
  WHERE hadm_id NOT IN (SELECT hadm_id FROM septic_shock_admissions)
),
-- Identify admissions with an ICU stay starting within Day 1 of hospital admission
day1_icu_stays AS (
    SELECT DISTINCT
        s.subject_id,
        s.hadm_id,
        TRUE AS had_day1_icu
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a_inner
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
        ON a_inner.hadm_id = s.hadm_id AND a_inner.subject_id = s.subject_id
    WHERE s.intime >= a_inner.admittime AND s.intime < DATETIME_ADD(a_inner.admittime, INTERVAL 1 DAY)
),
-- Main patient cohort with all derived attributes
patient_cohort AS (
    SELECT
        adm.subject_id,
        adm.hadm_id,
        p.gender,
        p.anchor_age,
        adm.admittime,
        adm.dischtime,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
        adm.hospital_expire_flag,
        -- Calculate days from admission to death; NULL if not expired in hospital or deathtime missing
        DATE_DIFF(adm.deathtime, adm.admittime, DAY) AS days_to_death_if_died,
        -- Determine Day-1 ICU status
        CASE
            WHEN day1_icu.had_day1_icu IS NOT NULL THEN 'Yes'
            ELSE 'No'
        END AS day1_icu_status,
        -- Categorize LOS
        CASE
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) <= 3 THEN '=<3 days'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6 days'
            WHEN DATE_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10 days'
            ELSE '>10 days'
        END AS los_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    JOIN eligible_admissions ea -- Filter for sepsis (excluding septic shock)
        ON adm.hadm_id = ea.hadm_id
    LEFT JOIN day1_icu_stays day1_icu -- Add Day-1 ICU status without filtering out non-ICU patients
        ON adm.subject_id = day1_icu.subject_id AND adm.hadm_id = day1_icu.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 86 AND 96
)
-- Final aggregation to calculate required metrics
SELECT
    cohort.los_category,
    cohort.day1_icu_status,
    -- In-hospital mortality (%)
    ROUND(COUNT(CASE WHEN cohort.hospital_expire_flag = 1 THEN 1 END) * 100.0 / COUNT(*), 2) AS in_hospital_mortality_percent,
    -- Median days to death for those who died in hospital
    -- PERCENTILE_CONT handles NULLs by ignoring them, which is appropriate for days_to_death_if_died
    COALESCE(CAST(PERCENTILE_CONT(cohort.days_to_death_if_died, 0.5) AS NUMERIC), 0) AS median_days_to_death,
    COUNT(cohort.hadm_id) AS total_patients_in_group -- Added for context
FROM patient_cohort cohort
GROUP BY
    cohort.los_category,
    cohort.day1_icu_status
ORDER BY
    CASE cohort.los_category -- Ensure logical ordering of LOS categories
        WHEN '=<3 days' THEN 1
        WHEN '4-6 days' THEN 2
        WHEN '7-10 days' THEN 3
        ELSE 4
    END,
    cohort.day1_icu_status;