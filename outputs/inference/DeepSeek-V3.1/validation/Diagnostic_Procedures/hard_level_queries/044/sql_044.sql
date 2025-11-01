WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,
        ie.outtime,
        p.anchor_age,
        p.gender,
        adm.admittime,
        adm.dischtime,
        adm.hospital_expire_flag,
        DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON ie.hadm_id = adm.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 82 AND 92
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
            INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
                ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
            WHERE diag.hadm_id = ie.hadm_id
                AND d.icd_code = 'R57.0'
                AND d.icd_version = 10
        )
),

procedures_first_24h AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY c.stay_id
),

cohort_with_procedures AS (
    SELECT 
        c.*,
        COALESCE(p.procedure_count, 0) AS procedure_count
    FROM cohort c
    LEFT JOIN procedures_first_24h p
        ON c.stay_id = p.stay_id
),

quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM cohort_with_procedures
)

SELECT 
    quintile,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los_days) AS mean_hospital_los_days,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;