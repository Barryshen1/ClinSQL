WITH first_icu_stays AS (
    SELECT 
        subject_id,
        hadm_id,
        stay_id,
        intime,
        outtime,
        los,
        ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS stay_seq
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
sepsis_patients AS (
    SELECT 
        diag.subject_id,
        diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE 
        (d.icd_code LIKE 'A41%' OR d.icd_code = 'R65.20' OR d.icd_code = 'R65.21')  -- ICD-10 sepsis
        OR (d.icd_code LIKE '038%' OR d.icd_code = '995.52')  -- ICD-9 sepsis
),
cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        icu.hadm_id,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        icu.los,
        adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN first_icu_stays icu
        ON p.subject_id = icu.subject_id AND icu.stay_seq = 1
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON icu.hadm_id = adm.hadm_id
    INNER JOIN sepsis_patients sep
        ON icu.hadm_id = sep.hadm_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 83 AND 93
),
procedures_in_first_72h AS (
    SELECT 
        c.subject_id,
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.subject_id, c.stay_id
),
cohort_with_procedures AS (
    SELECT 
        c.*,
        COALESCE(p.procedure_count, 0) AS procedure_count
    FROM cohort c
    LEFT JOIN procedures_in_first_72h p
        ON c.stay_id = p.stay_id
),
quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY procedure_count) AS intensity_quartile
    FROM cohort_with_procedures
)
SELECT 
    intensity_quartile,
    COUNT(*) AS num_patients,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los_days,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percent
FROM quartiles
GROUP BY intensity_quartile
ORDER BY intensity_quartile;