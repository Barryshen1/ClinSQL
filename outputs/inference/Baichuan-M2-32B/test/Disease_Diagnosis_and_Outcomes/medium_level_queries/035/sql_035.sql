WITH patient_admissions AS (
    SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag,
        -- Calculate LOS in days
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 69 AND 79
        AND a.dischtime IS NOT NULL  -- Exclude ongoing admissions
),
gi_diagnoses AS (
    SELECT
        d.hadm_id,
        d.icd_code,
        d.seq_num,
        di.icd_version,
        di.long_title,
        -- Classify as upper or lower GI bleed using ICD-10 codes
        CASE
            WHEN di.icd_code LIKE 'K25%' THEN 'upper'
            WHEN di.icd_code LIKE 'K52%' THEN 'lower'
            ELSE NULL
        END AS gi_type
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE
        di.icd_version = '10'
        AND (
            di.icd_code LIKE 'K25%'  -- Upper GI bleed
            OR di.icd_code LIKE 'K52%'  -- Lower GI bleed
        )
),
first_gi_diagnosis AS (
    SELECT
        hadm_id,
        gi_type
    FROM (
        SELECT
            hadm_id,
            gi_type,
            ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS rn
        FROM gi_diagnoses
    ) ranked
    WHERE rn = 1  -- First GI bleed diagnosis per admission
),
icu_info AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        -- ICU admission rate: 1 if any ICU stay during admission
        CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admitted,
        -- ICU status on day 1: 1 if ICU stay started within first 24 hours
        CASE
            WHEN i.intime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY) THEN 1
            ELSE 0
        END AS icu_day1
    FROM patient_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
combined_data AS (
    SELECT
        f.gi_type,
        p.los_days,
        -- Categorize LOS
        CASE
            WHEN p.los_days BETWEEN 1 AND 2 THEN '1-2'
            WHEN p.los_days BETWEEN 3 AND 5 THEN '3-5'
            WHEN p.los_days BETWEEN 6 AND 9 THEN '6-9'
            WHEN p.los_days >= 10 THEN '>=10'
            ELSE 'unknown'
        END AS los_category,
        i.icu_day1,
        p.hospital_expire_flag,
        i.icu_admitted
    FROM patient_admissions p
    INNER JOIN first_gi_diagnosis f
        ON p.hadm_id = f.hadm_id
    INNER JOIN icu_info i
        ON p.hadm_id = i.hadm_id
)
SELECT
    gi_type,
    los_category,
    icu_day1,
    -- Calculate mortality rate
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_rate,
    -- Calculate ICU admission rate (among the cohort in this group)
    SUM(icu_admitted) * 100.0 / COUNT(*) AS icu_admission_rate,
    COUNT(*) AS num_patients  -- Optional: to show sample size
FROM combined_data
GROUP BY gi_type, los_category, icu_day1
ORDER BY gi_type, los_category, icu_day1;