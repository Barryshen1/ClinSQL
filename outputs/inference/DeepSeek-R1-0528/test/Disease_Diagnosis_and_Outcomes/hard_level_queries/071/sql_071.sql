WITH patient_admissions AS (
    SELECT 
        adm.subject_id, 
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.deathtime, 
        adm.hospital_expire_flag,
        p.gender, 
        p.anchor_age AS age,
        p.dod
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON adm.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 68 AND 78
),
ami_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
        (icd_version = 9 AND icd_code LIKE '410%') OR
        (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
icu_admissions AS (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
complication_admissions AS (
    SELECT 
        hadm_id,
        MAX(CASE 
            WHEN (icd_version = 9 AND (
                    icd_code LIKE '584%' OR 
                    icd_code LIKE '430%' OR 
                    icd_code LIKE '431%' OR 
                    icd_code LIKE '432%' OR 
                    icd_code LIKE '433%' OR 
                    icd_code LIKE '434%' OR 
                    icd_code LIKE '436%' OR 
                    icd_code LIKE '437%' OR 
                    icd_code LIKE '438%'
                )) OR
                (icd_version = 10 AND (
                    icd_code LIKE 'N17%' OR 
                    icd_code LIKE 'I60%' OR 
                    icd_code LIKE 'I61%' OR 
                    icd_code LIKE 'I62%' OR 
                    icd_code LIKE 'I63%' OR 
                    icd_code LIKE 'I64%' OR 
                    icd_code LIKE 'I65%' OR 
                    icd_code LIKE 'I66%' OR 
                    icd_code LIKE 'I67%' OR 
                    icd_code LIKE 'I68%' OR 
                    icd_code LIKE 'I69%'
                )) 
            THEN 1 ELSE 0 
        END) AS complication_flag
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
),
drg_severity AS (
    SELECT 
        hadm_id, 
        MAX(CAST(drg_severity AS INT64)) AS drg_severity
    FROM `physionet-data.mimiciv_3_1_hosp.drgcodes`
    WHERE drg_severity IS NOT NULL
    GROUP BY hadm_id
),
admission_data AS (
    SELECT 
        pa.*,
        CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ami,
        CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu,
        COALESCE(c.complication_flag, 0) AS complication_flag,
        d.drg_severity,
        CASE 
            WHEN (pa.deathtime IS NOT NULL AND pa.deathtime <= DATETIME_ADD(pa.admittime, INTERVAL 90 DAY)) 
                OR (pa.dod IS NOT NULL AND pa.dod <= DATE_ADD(DATE(pa.admittime), INTERVAL 90 DAY)) 
            THEN 1 ELSE 0 
        END AS mortality_90d,
        DATETIME_DIFF(pa.dischtime, pa.admittime, DAY) AS los_hospital
    FROM patient_admissions pa
    LEFT JOIN ami_admissions a ON pa.hadm_id = a.hadm_id
    LEFT JOIN icu_admissions i ON pa.hadm_id = i.hadm_id
    LEFT JOIN complication_admissions c ON pa.hadm_id = c.hadm_id
    LEFT JOIN drg_severity d ON pa.hadm_id = d.hadm_id
)
SELECT 
    'AMI with ICU' AS cohort,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(drg_severity, 4)[OFFSET(2)] AS median_risk_score,
    APPROX_QUANTILES(drg_severity, 4)[OFFSET(3)] - APPROX_QUANTILES(drg_severity, 4)[OFFSET(1)] AS iqr_risk_score,
    AVG(mortality_90d) * 100 AS mortality_90d_rate,
    AVG(complication_flag) * 100 AS complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(2)] AS median_survivor_los,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(3)] - 
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(1)] AS iqr_survivor_los
FROM admission_data
WHERE is_ami = 1 AND has_icu = 1
UNION ALL
SELECT 
    'General Inpatients' AS cohort,
    COUNT(*) AS num_admissions,
    NULL AS median_risk_score,
    NULL AS iqr_risk_score,
    AVG(mortality_90d) * 100 AS mortality_90d_rate,
    AVG(complication_flag) * 100 AS complication_rate,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(2)] AS median_survivor_los,
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(3)] - 
    APPROX_QUANTILES(CASE WHEN hospital_expire_flag = 0 THEN los_hospital END, 4 IGNORE NULLS)[OFFSET(1)] AS iqr_survivor_los
FROM admission_data
WHERE is_ami = 0;