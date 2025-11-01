WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        adm.hadm_id, 
        adm.admittime, 
        adm.dischtime, 
        adm.hospital_expire_flag,
        icu.stay_id,
        icu.intime,
        icu.outtime,
        -- Calculate hospital LOS in days
        DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hosp_los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
        ON adm.hadm_id = icu.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 44 AND 54
        AND d.long_title LIKE 'Acute myocardial infarction%'
    -- Get the first ICU stay per admission
    QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY icu.intime) = 1
),

procedures_72h AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON c.stay_id = pe.stay_id
        AND pe.starttime >= c.intime
        AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
    GROUP BY c.stay_id
),

cohort_with_procedures AS (
    SELECT 
        c.*,
        COALESCE(p.procedure_count, 0) AS procedure_count
    FROM cohort c
    LEFT JOIN procedures_72h p
        ON c.stay_id = p.stay_id
),

quartiles AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY procedure_count) AS quartile
    FROM cohort_with_procedures
)

SELECT 
    quartile,
    COUNT(*) AS n,
    ROUND(AVG(procedure_count), 2) AS mean_procedure_count,
    ROUND(AVG(hosp_los_days), 2) AS mean_hosp_los_days,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percentage
FROM quartiles
GROUP BY quartile
ORDER BY quartile;