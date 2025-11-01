WITH first_icu_stays AS (
    SELECT 
        ie.subject_id, 
        ie.hadm_id, 
        ie.stay_id,
        ie.intime,
        ie.outtime,
        ie.los,
        p.anchor_age,
        p.gender,
        ROW_NUMBER() OVER (PARTITION BY ie.subject_id ORDER BY ie.intime) AS stay_num
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
),
lower_gi_bleeding_patients AS (
    SELECT DISTINCT
        f.subject_id,
        f.hadm_id,
        f.stay_id,
        f.intime,
        f.outtime,
        f.los,
        f.anchor_age
    FROM first_icu_stays f
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON f.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE d.long_title LIKE '%lower gastrointestinal bleeding%'
        OR d.long_title LIKE '%hemorrhage of rectum%'
        OR d.long_title LIKE '%melena%'
        OR diag.icd_code IN ('K62.5', 'K92.1', 'K92.2')  -- ICD-10
        OR diag.icd_code IN ('578.1', '578.9')  -- ICD-9
    AND f.stay_num = 1  -- first ICU stay
),
procedures_first_48h AS (
    SELECT
        lgb.subject_id,
        lgb.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM lower_gi_bleeding_patients lgb
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON lgb.stay_id = pe.stay_id
        AND pe.starttime >= lgb.intime
        AND pe.starttime <= DATETIME_ADD(lgb.intime, INTERVAL 48 HOUR)
    GROUP BY lgb.subject_id, lgb.stay_id
),
cohort_with_procedures AS (
    SELECT
        lgb.subject_id,
        lgb.hadm_id,
        lgb.stay_id,
        lgb.los,
        lgb.anchor_age,
        COALESCE(p.procedure_count, 0) AS procedure_count,
        adm.hospital_expire_flag
    FROM lower_gi_bleeding_patients lgb
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON lgb.hadm_id = adm.hadm_id
    LEFT JOIN procedures_first_48h p
        ON lgb.subject_id = p.subject_id AND lgb.stay_id = p.stay_id
),
quintiles AS (
    SELECT
        subject_id,
        hadm_id,
        stay_id,
        los,
        procedure_count,
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM cohort_with_procedures
)
SELECT
    quintile,
    COUNT(*) AS num_patients,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los_days,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;