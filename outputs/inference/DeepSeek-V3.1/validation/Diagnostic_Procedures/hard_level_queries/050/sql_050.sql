WITH cohort AS (
    SELECT 
        ie.stay_id,
        ie.subject_id,
        ie.hadm_id,
        ie.intime,  -- Added intime for time filtering
        ie.los,
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
        AND p.anchor_age BETWEEN 76 AND 86
        AND (
            (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') 
            OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        )
),
procedure_counts AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    GROUP BY c.stay_id
),
with_quartiles AS (
    SELECT 
        c.stay_id,
        c.los,
        c.hospital_expire_flag,
        pc.procedure_count,
        NTILE(4) OVER (ORDER BY pc.procedure_count) AS quartile
    FROM cohort c
    INNER JOIN procedure_counts pc 
        ON c.stay_id = pc.stay_id
)
SELECT 
    quartile,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM with_quartiles
GROUP BY quartile
ORDER BY quartile;