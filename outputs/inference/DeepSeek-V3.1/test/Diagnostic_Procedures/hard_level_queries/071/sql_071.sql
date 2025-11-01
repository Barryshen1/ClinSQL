WITH base_cohort AS (
    SELECT 
        p.subject_id, 
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        -- Flag for ICH diagnosis (handling both ICD-9 and ICD-10)
        MAX(CASE 
            WHEN (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432')) 
              OR (d.icd_version = 10 AND (d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
            THEN 1 ELSE 0 
        END) AS has_ich
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON i.hadm_id = d.hadm_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 50 AND 60
    GROUP BY p.subject_id, p.anchor_age, i.hadm_id, i.stay_id, i.intime, i.outtime
),
procedure_burden AS (
    SELECT 
        bc.stay_id,
        COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM base_cohort bc
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON bc.stay_id = pe.stay_id
        AND pe.starttime >= bc.intime
        AND pe.starttime < DATETIME_ADD(bc.intime, INTERVAL 72 HOUR)
    GROUP BY bc.stay_id
),
los_mortality AS (
    SELECT
        bc.subject_id,
        bc.hadm_id,
        bc.has_ich,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital,
        a.hospital_expire_flag
    FROM base_cohort bc
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON bc.hadm_id = a.hadm_id
)
SELECT 
    'ICH' AS cohort,
    COUNT(DISTINCT bc.stay_id) AS num_stays,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(25)] AS p25_procedures,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(50)] AS median_procedures,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    MAX(pb.num_procedures) AS max_procedures,
    AVG(lm.los_hospital) AS avg_los,
    AVG(lm.hospital_expire_flag) AS mortality_rate
FROM base_cohort bc
INNER JOIN procedure_burden pb ON bc.stay_id = pb.stay_id
INNER JOIN los_mortality lm ON bc.hadm_id = lm.hadm_id
WHERE bc.has_ich = 1
GROUP BY cohort
UNION ALL
SELECT 
    'Non-ICH' AS cohort,
    COUNT(DISTINCT bc.stay_id) AS num_stays,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(25)] AS p25_procedures,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(50)] AS median_procedures,
    APPROX_QUANTILES(pb.num_procedures, 100)[OFFSET(90)] AS p90_procedures,
    MAX(pb.num_procedures) AS max_procedures,
    AVG(lm.los_hospital) AS avg_los,
    AVG(lm.hospital_expire_flag) AS mortality_rate
FROM base_cohort bc
INNER JOIN procedure_burden pb ON bc.stay_id = pb.stay_id
INNER JOIN los_mortality lm ON bc.hadm_id = lm.hadm_id
WHERE bc.has_ich = 0
GROUP BY cohort;