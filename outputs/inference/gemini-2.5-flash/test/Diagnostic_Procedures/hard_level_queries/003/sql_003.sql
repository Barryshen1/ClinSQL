WITH icu_base AS (
    -- Base CTE to gather essential ICU stay, admission, and patient demographic data
    SELECT
        ie.subject_id,
        ie.hadm_id,
        ie.stay_id,
        p.gender,
        p.anchor_age,
        ie.intime AS icu_intime,
        ad.admittime AS hosp_admittime,
        ad.dischtime AS hosp_dischtime,
        ad.hospital_expire_flag,
        TIMESTAMP_DIFF(ad.dischtime, ad.admittime, HOUR) / 24.0 AS hospital_los_days -- Hospital LOS in days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON ie.hadm_id = ad.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
),
ards_diagnoses AS (
    -- CTE to identify admissions with an ARDS diagnosis
    SELECT DISTINCT
        d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE
        (d.icd_version = 9 AND d.icd_code = '51882') -- ICD-9 code for Acute Respiratory Distress Syndrome
        OR (d.icd_version = 10 AND d.icd_code = 'J80') -- ICD-10 code for Acute Respiratory Distress Syndrome
),
procedures_first_24h AS (
    -- CTE to calculate the number of distinct procedures in the first 24 hours for each ICU stay
    SELECT
        pe.stay_id,
        COUNT(DISTINCT pe.itemid) AS distinct_procedures_24h -- Count distinct itemids for diagnostic intensity
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN icu_base ib
        ON pe.stay_id = ib.stay_id
    WHERE
        pe.starttime IS NOT NULL
        AND pe.starttime >= ib.icu_intime
        AND pe.starttime <= TIMESTAMP_ADD(ib.icu_intime, INTERVAL 24 HOUR) -- Procedures within first 24 hours
    GROUP BY pe.stay_id
),
cohort_data AS (
    -- Combine base ICU data with procedure counts and ARDS flags
    SELECT
        ib.*,
        COALESCE(pf.distinct_procedures_24h, 0) AS distinct_procedures_24h, -- Default to 0 if no procedures in first 24h
        CASE WHEN ard.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
    FROM icu_base ib
    LEFT JOIN procedures_first_24h pf
        ON ib.stay_id = pf.stay_id
    LEFT JOIN ards_diagnoses ard
        ON ib.hadm_id = ard.hadm_id
),
ards_female_84_94_cohort AS (
    -- Filter for the specific ARDS cohort
    SELECT
        cd.distinct_procedures_24h,
        cd.hospital_los_days,
        cd.hospital_expire_flag
    FROM cohort_data cd
    WHERE
        cd.has_ards = 1
        AND cd.gender = 'F'
        AND cd.anchor_age BETWEEN 84 AND 94
),
general_icu_cohort AS (
    -- Represents the general ICU population
    SELECT
        cd.distinct_procedures_24h,
        cd.hospital_los_days,
        cd.hospital_expire_flag
    FROM cohort_data cd
)
-- Final aggregation and comparison of metrics for both cohorts
SELECT
    'ARDS Female 84-94 ICU Patients' AS cohort_name,
    PERCENTILE_CONT(distinct_procedures_24h, 0.25) AS q25_distinct_procedures_24h,
    PERCENTILE_CONT(distinct_procedures_24h, 0.75) AS q75_distinct_procedures_24h,
    PERCENTILE_CONT(distinct_procedures_24h, 0.95) AS q95_distinct_procedures_24h,
    AVG(hospital_los_days) AS avg_hospital_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM ards_female_84_94_cohort

UNION ALL

SELECT
    'General ICU Patients' AS cohort_name,
    PERCENTILE_CONT(distinct_procedures_24h, 0.25) AS q25_distinct_procedures_24h,
    PERCENTILE_CONT(distinct_procedures_24h, 0.75) AS q75_distinct_procedures_24h,
    PERCENTILE_CONT(distinct_procedures_24h, 0.95) AS q95_distinct_procedures_24h,
    AVG(hospital_los_days) AS avg_hospital_los_days,
    AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM general_icu_cohort;