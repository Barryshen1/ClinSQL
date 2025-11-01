WITH ami_cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
        ON ie.hadm_id = adm.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
        ON ie.hadm_id = diag.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') 
            OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        )
),

-- Count distinct procedures per stay in first 72 hours
ami_procedures AS (
    SELECT 
        ac.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM ami_cohort ac
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON ac.stay_id = pe.stay_id
        AND pe.starttime >= ac.intime
        AND pe.starttime <= DATETIME_ADD(ac.intime, INTERVAL 72 HOUR)
    GROUP BY ac.stay_id
),

-- Compute 90th percentile of procedure count
ami_diag_intensity AS (
    SELECT 
        PERCENTILE_CONT(num_procedures, 0.9) OVER() AS p90_procedures
    FROM ami_procedures
    LIMIT 1
),

-- Outcomes for AMI cohort
ami_outcomes AS (
    SELECT 
        'AMI' AS cohort,
        AVG(DATETIME_DIFF(ac.dischtime, ac.admittime, DAY)) AS mean_los,
        AVG(ac.hospital_expire_flag) AS mortality_rate
    FROM ami_cohort ac
),

-- Control group: male ICU patients aged 42-52 without AMI
control_cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
        ON ie.hadm_id = adm.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 42 AND 52
        AND NOT EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
            WHERE ie.hadm_id = diag.hadm_id
            AND (
                (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') 
                OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
                OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
            )
        )
),

-- Outcomes for control cohort
control_outcomes AS (
    SELECT 
        'Control' AS cohort,
        AVG(DATETIME_DIFF(cc.dischtime, cc.admittime, DAY)) AS mean_los,
        AVG(cc.hospital_expire_flag) AS mortality_rate
    FROM control_cohort cc
)

-- Final output
SELECT 
    (SELECT p90_procedures FROM ami_diag_intensity) AS p90_diagnostic_intensity,
    ami.cohort,
    ami.mean_los AS mean_hospital_los_ami,
    ami.mortality_rate AS mortality_rate_ami,
    ctrl.mean_los AS mean_hospital_los_control,
    ctrl.mortality_rate AS mortality_rate_control
FROM ami_outcomes ami, control_outcomes ctrl;