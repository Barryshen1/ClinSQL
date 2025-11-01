WITH AdmissionsAMI AS (
    -- Step 1 & 2a: Identify admissions with AMI as primary diagnosis and join with patient demographics
    SELECT
        ad.subject_id,
        ad.hadm_id,
        p.gender,
        (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) AS age_at_admission,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ad.subject_id = p.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON ad.hadm_id = di.hadm_id
    WHERE
        p.gender = 'F'
        AND (p.anchor_age + (EXTRACT(YEAR FROM ad.admittime) - p.anchor_year)) BETWEEN 52 AND 62
        -- Filter for AMI ICD codes (ICD-9 and ICD-10) as primary diagnosis
        AND di.seq_num = 1
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410%') -- ICD-9 AMI codes
            OR
            (di.icd_version = 10 AND di.icd_code LIKE 'I21%') -- ICD-10 AMI codes
        )
),
FirstTroponinTMeasurement AS (
    -- Step 3: Find the first Troponin T measurement for each relevant admission
    SELECT
        le.hadm_id,
        le.valuenum AS troponin_t_value,
        ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE
        le.itemid = 51902 -- Itemid for Troponin T (quantitative) in MIMIC-IV
        AND le.valuenum IS NOT NULL
        AND le.valueuom = 'ng/mL' -- Ensure the unit is correct for the threshold
),
CohortFiltered AS (
    -- Step 2b & 3b: Filter admissions by age and first Troponin T value
    SELECT
        ami.subject_id,
        ami.hadm_id,
        ami.age_at_admission,
        DATETIME_DIFF(ami.dischtime, ami.admittime, HOUR) / 24.0 AS los_days,
        ft.troponin_t_value AS first_troponin_t,
        ami.hospital_expire_flag
    FROM
        AdmissionsAMI ami
    JOIN
        FirstTroponinTMeasurement ft
        ON ami.hadm_id = ft.hadm_id
    WHERE
        ft.rn = 1 -- Only consider the first Troponin T measurement
        AND ft.troponin_t_value > 0.01 -- Filter by the specified threshold
)
-- Step 4: Aggregate and report the required statistics
SELECT
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    ROUND(AVG(age_at_admission), 2) AS mean_age,
    ROUND(AVG(los_days), 2) AS mean_los_days,
    ROUND(AVG(first_troponin_t), 4) AS mean_first_troponin_t,
    -- Calculate median using APPROX_QUANTILES for BigQuery
    ROUND(APPROX_QUANTILES(first_troponin_t, 100)[OFFSET(50)], 4) AS median_first_troponin_t,
    ROUND(MIN(first_troponin_t), 4) AS min_first_troponin_t,
    ROUND(MAX(first_troponin_t), 4) AS max_first_troponin_t,
    SUM(hospital_expire_flag) AS in_hospital_mortality_count
FROM
    CohortFiltered;