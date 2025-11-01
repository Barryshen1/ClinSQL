WITH cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON i.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 44 AND 54
        AND d.long_title LIKE '%pulmonary embolism%'
        -- Also filter for first ICU stay per hospitalization? The question says "first ICU stay"
        -- We use ROW_NUMBER to get the first ICU stay per hadm_id
        AND i.stay_id = (
            SELECT MIN(i2.stay_id)
            FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
            WHERE i2.hadm_id = i.hadm_id
        )
),
procedures_count AS (
    SELECT 
        c.subject_id,
        c.stay_id,
        c.hadm_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.subject_id, c.stay_id, c.hadm_id
),
cohort_with_procedures AS (
    SELECT 
        c.*,
        COALESCE(pc.procedure_count, 0) AS procedure_count
    FROM cohort c
    LEFT JOIN procedures_count pc
        ON c.stay_id = pc.stay_id
),
quintiles AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM cohort_with_procedures
)
SELECT 
    quintile,
    AVG(procedure_count) AS avg_procedure_count,
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_hospital_los_days,
    100.0 * SUM(hospital_expire_flag) / COUNT(*) AS mortality_percentage
FROM quintiles
GROUP BY quintile
ORDER BY quintile;