WITH
-- Step 1: Find all hospital admissions with a pneumonia diagnosis.
pneumonia_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
    WHERE LOWER(long_title) LIKE '%pneumonia%'
),

-- Step 2: Define the primary cohort of patients based on demographics, diagnosis, and ICU admission.
-- We also rank ICU stays to identify the first one for each hospital admission.
cohort AS (
    SELECT
        p.subject_id,
        adm.hadm_id,
        icu.stay_id,
        adm.admittime,
        adm.deathtime,
        adm.hospital_expire_flag,
        ROW_NUMBER() OVER(PARTITION BY adm.hadm_id ORDER BY icu.intime ASC) as icu_stay_rank
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON p.subject_id = adm.subject_id
    JOIN pneumonia_admissions pa ON adm.hadm_id = pa.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON adm.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'M'
        AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 88 AND 98
),

-- Step 3: Identify ARDS diagnosis via ICD codes for the hospital admissions in our cohort.
ards_diagnoses AS (
    SELECT DISTINCT
        hadm_id,
        1 AS has_ards
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
        hadm_id IN (SELECT hadm_id FROM cohort)
        AND icd_code IN (
            'J80',      -- ICD-10 for Acute respiratory distress syndrome
            '518.82'    -- ICD-9 for Acute respiratory distress syndrome
        )
),

-- Step 4: Retrieve the 24-hour SOFA score for the first ICU stay.
first_day_sofa AS (
    SELECT
        c.hadm_id,
        s.sofa_24 AS sofa_score
    FROM cohort c
    JOIN `physionet-data.mimiciv_derived.sofa` s ON c.stay_id = s.stay_id
    WHERE
        c.icu_stay_rank = 1  -- Only for the first ICU stay
),

-- Step 5: Determine if AKI occurred at any point during the first ICU stay using KDIGO stages.
aki_diagnoses AS (
    SELECT
        c.hadm_id,
        MAX(CASE WHEN ks.kdigo_stage > 0 THEN 1 ELSE 0 END) AS has_aki
    FROM cohort c
    JOIN `physionet-data.mimiciv_derived.kdigo_stages` ks ON c.stay_id = ks.stay_id
    WHERE
        c.icu_stay_rank = 1 -- Only for the first ICU stay
    GROUP BY c.hadm_id
),

-- Step 6: Combine all cohort data, diagnoses, and scores into a single table per admission.
final_cohort_data AS (
    SELECT
        c.subject_id,
        c.hadm_id,
        c.hospital_expire_flag,
        DATETIME_DIFF(c.deathtime, c.admittime, DAY) AS survival_days,
        sofa.sofa_score,
        COALESCE(ards.has_ards, 0) AS has_ards,
        COALESCE(aki.has_aki, 0) AS has_aki
    FROM (SELECT * FROM cohort WHERE icu_stay_rank = 1) c -- Use only the first ICU stay record per admission
    LEFT JOIN first_day_sofa sofa ON c.hadm_id = sofa.hadm_id
    LEFT JOIN ards_diagnoses ards ON c.hadm_id = ards.hadm_id
    LEFT JOIN aki_diagnoses aki ON c.hadm_id = aki.hadm_id
)

-- Step 7: Aggregate the results to generate the final report.
SELECT
    -- Cohort size
    COUNT(DISTINCT hadm_id) AS cohort_admission_count,

    -- Composite risk score (SOFA) distribution
    MIN(sofa_score) AS sofa_min,
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(25)] AS sofa_p25,
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(50)] AS sofa_median,
    APPROX_QUANTILES(sofa_score, 100)[OFFSET(75)] AS sofa_p75,
    MAX(sofa_score) AS sofa_max,

    -- Outcome rates as percentages
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(hadm_id)) * 100 AS in_hospital_mortality_rate_percent,
    SAFE_DIVIDE(SUM(has_aki), COUNT(hadm_id)) * 100 AS aki_rate_percent,
    SAFE_DIVIDE(SUM(has_ards), COUNT(hadm_id)) * 100 AS ards_rate_percent,

    -- Median survival for decedents
    APPROX_QUANTILES(
        IF(hospital_expire_flag = 1, survival_days, NULL),
    100)[OFFSET(50)] AS median_survival_days_for_decedents

FROM final_cohort_data;