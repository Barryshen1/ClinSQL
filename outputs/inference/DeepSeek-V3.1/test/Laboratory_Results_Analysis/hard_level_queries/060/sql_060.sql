WITH cardiac_arrest_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND diag.icd_code LIKE 'I46%'
        AND diag.icd_version = 10
),
control_cohort AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    WHERE 
        pat.gender = 'F'
        AND pat.anchor_age BETWEEN 52 AND 62
        AND adm.hadm_id NOT IN (
            SELECT hadm_id 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
            WHERE icd_code LIKE 'I46%' AND icd_version = 10
        )
),
critical_lab_counts AS (
    SELECT 
        le.hadm_id,
        COUNT(*) AS critical_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN cardiac_arrest_cohort cac
        ON le.hadm_id = cac.hadm_id
    WHERE 
        le.charttime BETWEEN cac.admittime AND DATETIME_ADD(cac.admittime, INTERVAL 48 HOUR)
        AND le.flag IS NOT NULL
    GROUP BY le.hadm_id
),
control_critical_lab_counts AS (
    SELECT 
        le.hadm_id,
        COUNT(*) AS critical_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN control_cohort cc
        ON le.hadm_id = cc.hadm_id
    WHERE 
        le.charttime BETWEEN cc.admittime AND DATETIME_ADD(cc.admittime, INTERVAL 48 HOUR)
        AND le.flag IS NOT NULL
    GROUP BY le.hadm_id
),
cardiac_arrest_with_labs AS (
    SELECT 
        cac.subject_id,
        cac.hadm_id,
        cac.los_days,
        cac.hospital_expire_flag,
        COALESCE(clc.critical_lab_count, 0) AS critical_lab_count
    FROM cardiac_arrest_cohort cac
    LEFT JOIN critical_lab_counts clc
        ON cac.hadm_id = clc.hadm_id
),
control_with_labs AS (
    SELECT 
        cc.subject_id,
        cc.hadm_id,
        cc.los_days,
        cc.hospital_expire_flag,
        COALESCE(cclc.critical_lab_count, 0) AS critical_lab_count
    FROM control_cohort cc
    LEFT JOIN control_critical_lab_counts cclc
        ON cc.hadm_id = cclc.hadm_id
)
SELECT 
    'Cardiac Arrest' AS cohort,
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(1)] AS q1_instability_score,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(2)] AS median_instability_score,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(3)] AS q3_instability_score,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_percent
FROM cardiac_arrest_with_labs

UNION ALL

SELECT 
    'Control' AS cohort,
    COUNT(*) AS n_patients,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(1)] AS q1_instability_score,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(2)] AS median_instability_score,
    APPROX_QUANTILES(critical_lab_count, 4)[OFFSET(3)] AS q3_instability_score,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_percent
FROM control_with_labs;