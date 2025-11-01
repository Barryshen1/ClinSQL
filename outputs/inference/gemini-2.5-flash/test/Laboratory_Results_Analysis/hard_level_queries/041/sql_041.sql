WITH
-- 1. Identify the Heart Failure (HF) patient cohort based on age, gender, and diagnosis.
hf_admissions AS (
    SELECT
        DISTINCT ad.subject_id,
        ad.hadm_id,
        ad.admittime,
        ad.dischtime,
        ad.hospital_expire_flag
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON
        ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 54 AND 64
        AND ad.hadm_id IN (
            SELECT
                di.hadm_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                (di.icd_version = 9 AND di.icd_code LIKE '428%') -- ICD-9 codes for Heart Failure
                OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%') -- ICD-10 codes for Heart Failure
        )
),
-- 2. Calculate initial lab instability score for HF admissions (count distinct abnormal lab items in 48h).
hf_raw_scores AS (
    SELECT
        ha.hadm_id,
        COUNT(DISTINCT le.itemid) AS lab_instability_score
    FROM
        hf_admissions ha
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON
        ha.subject_id = le.subject_id
        AND ha.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ha.admittime AND DATETIME_ADD(ha.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ha.hadm_id
),
-- 3. Combine original HF admissions with their calculated scores, assigning 0 if no abnormal labs found.
hf_all_admissions_with_scores AS (
    SELECT
        ha.subject_id,
        ha.hadm_id,
        ha.admittime,
        ha.dischtime,
        ha.hospital_expire_flag,
        COALESCE(hrs.lab_instability_score, 0) AS lab_instability_score
    FROM
        hf_admissions ha
    LEFT JOIN
        hf_raw_scores hrs
    ON
        ha.hadm_id = hrs.hadm_id
),
-- 4. Determine the 95th-percentile threshold for the lab instability score in the HF cohort.
percentile_threshold AS (
    SELECT
        PERCENTILE_CONT(lab_instability_score, 0.95) OVER () AS threshold_score
    FROM
        hf_all_admissions_with_scores
    LIMIT 1 -- To ensure only one row is returned
),
-- 5. Identify the HF high-instability cohort (scores >= 95th percentile).
hf_high_instability_cohort AS (
    SELECT
        hals.subject_id,
        hals.hadm_id,
        hals.admittime,
        hals.dischtime,
        hals.hospital_expire_flag,
        hals.lab_instability_score
    FROM
        hf_all_admissions_with_scores hals,
        percentile_threshold pt
    WHERE
        hals.lab_instability_score >= pt.threshold_score
),
-- 6. Identify the age-matched control cohort (similar age/gender, but without HF diagnosis).
control_admissions AS (
    SELECT
        DISTINCT ad.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    ON
        ad.subject_id = pa.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 54 AND 64
        AND ad.hadm_id NOT IN ( -- Exclude any HF diagnoses
            SELECT
                di.hadm_id
            FROM
                `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE
                (di.icd_version = 9 AND di.icd_code LIKE '428%')
                OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
        )
),
-- 7. Calculate lab instability score for control admissions.
control_raw_scores AS (
    SELECT
        ca.hadm_id,
        COUNT(DISTINCT le.itemid) AS lab_instability_score
    FROM
        control_admissions ca
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON
        ca.subject_id = le.subject_id
        AND ca.hadm_id = le.hadm_id
    WHERE
        le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
        AND le.flag = 'abnormal'
    GROUP BY
        ca.hadm_id
),
-- 8. Combine original control admissions with their calculated scores, assigning 0 if no abnormal labs found.
control_all_admissions_with_scores AS (
    SELECT
        ca.subject_id,
        ca.hadm_id,
        ca.admittime,
        COALESCE(crs.lab_instability_score, 0) AS lab_instability_score
    FROM
        control_admissions ca
    LEFT JOIN
        control_raw_scores crs
    ON
        ca.hadm_id = crs.hadm_id
)
-- Final aggregation and reporting
SELECT
    'HF_High_Instability_Cohort' AS cohort_type,
    (SELECT pt.threshold_score FROM percentile_threshold pt) AS percentile_95_lab_instability_threshold,
    COUNT(DISTINCT hih.hadm_id) AS num_admissions_in_cohort,
    AVG(hih.lab_instability_score) AS mean_critical_lab_rate_score,
    AVG(DATETIME_DIFF(hih.dischtime, hih.admittime, HOUR) / 24.0) AS mean_hospital_los_days,
    SUM(CASE WHEN hih.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_in_hospital_mortality,
    SAFE_DIVIDE(SUM(CASE WHEN hih.hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(DISTINCT hih.hadm_id)) AS in_hospital_mortality_rate
FROM
    hf_high_instability_cohort hih

UNION ALL

SELECT
    'Control_Cohort' AS cohort_type,
    NULL AS percentile_95_lab_instability_threshold, -- Not applicable for control cohort
    COUNT(DISTINCT cal.hadm_id) AS num_admissions_in_cohort,
    AVG(cal.lab_instability_score) AS mean_critical_lab_rate_score,
    NULL AS mean_hospital_los_days, -- Not requested for control cohort
    NULL AS num_in_hospital_mortality, -- Not requested for control cohort
    NULL AS in_hospital_mortality_rate -- Not requested for control cohort
FROM
    control_all_admissions_with_scores cal;