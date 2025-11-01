WITH first_icu_stays AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        p.gender,
        p.anchor_age,
        a.hospital_expire_flag,
        DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
        ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS stay_num
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON ie.hadm_id = a.hadm_id
),

ards_patients AS (
    SELECT 
        DISTINCT diag.subject_id, 
        diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.long_title LIKE '%acute respiratory distress syndrome%'
        OR diag.icd_code IN ('518.82', 'J80')
),

procedures_first_72h AS (
    SELECT 
        pe.subject_id,
        pe.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    INNER JOIN first_icu_stays fis
        ON pe.stay_id = fis.stay_id
    WHERE pe.starttime BETWEEN fis.intime AND DATETIME_ADD(fis.intime, INTERVAL 72 HOUR)
    GROUP BY pe.subject_id, pe.stay_id
),

target_cohort AS (
    SELECT 
        fis.subject_id,
        fis.stay_id,
        fis.gender,
        fis.anchor_age,
        fis.los_hospital,
        fis.hospital_expire_flag,
        COALESCE(pf.num_procedures, 0) AS num_procedures
    FROM first_icu_stays fis
    INNER JOIN ards_patients ards
        ON fis.hadm_id = ards.hadm_id AND fis.subject_id = ards.subject_id
    LEFT JOIN procedures_first_72h pf
        ON fis.stay_id = pf.stay_id
    WHERE fis.stay_num = 1
        AND fis.gender = 'F'
        AND fis.anchor_age BETWEEN 37 AND 47
),

all_icu_cohort AS (
    SELECT 
        fis.subject_id,
        fis.stay_id,
        fis.gender,
        fis.anchor_age,
        fis.los_hospital,
        fis.hospital_expire_flag,
        COALESCE(pf.num_procedures, 0) AS num_procedures
    FROM first_icu_stays fis
    LEFT JOIN procedures_first_72h pf
        ON fis.stay_id = pf.stay_id
    WHERE fis.stay_num = 1
)

SELECT 
    'Target Cohort (F 37-47 with ARDS)' AS cohort,
    COUNT(*) AS n_patients,
    MIN(num_procedures) AS min_procedures,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    AVG(los_hospital) AS mean_los_hospital,
    AVG(hospital_expire_flag) AS in_hospital_mortality
FROM target_cohort

UNION ALL

SELECT 
    'All ICU Patients' AS cohort,
    COUNT(*) AS n_patients,
    MIN(num_procedures) AS min_procedures,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75_procedures,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    AVG(los_hospital) AS mean_los_hospital,
    AVG(hospital_expire_flag) AS in_hospital_mortality
FROM all_icu_cohort;