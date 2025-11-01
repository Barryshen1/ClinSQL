WITH first_icu_stay AS (
    SELECT 
        i.subject_id,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
),
cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        fis.hadm_id,
        fis.stay_id,
        fis.intime,
        fis.los,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN first_icu_stay fis ON p.subject_id = fis.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
    WHERE p.gender = 'F' 
        AND p.anchor_age BETWEEN 87 AND 97
        AND fis.rn = 1
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi 
                ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
            WHERE di.subject_id = p.subject_id 
                AND di.hadm_id = fis.hadm_id
                AND (ddi.long_title LIKE '%gastrointestinal bleeding%' 
                     OR ddi.long_title LIKE '%lower gastrointestinal bleeding%' 
                     OR ddi.long_title LIKE '%rectal hemorrhage%' 
                     OR ddi.long_title LIKE '%colonic hemorrhage%')
        )
),
procedure_counts AS (
    SELECT 
        c.stay_id,
        COUNT(DISTINCT pe.itemid) AS procedure_count
    FROM cohort c
    JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON c.stay_id = pe.stay_id
    WHERE pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    GROUP BY c.stay_id
),
cohort_with_procedures AS (
    SELECT 
        c.*,
        COALESCE(pc.procedure_count, 0) AS procedure_count
    FROM cohort c
    LEFT JOIN procedure_counts pc ON c.stay_id = pc.stay_id
),
quintiles AS (
    SELECT 
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile,
        procedure_count,
        los,
        hospital_expire_flag
    FROM cohort_with_procedures
)
SELECT 
    quintile,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(los) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM quintiles
GROUP BY quintile
ORDER BY quintile;