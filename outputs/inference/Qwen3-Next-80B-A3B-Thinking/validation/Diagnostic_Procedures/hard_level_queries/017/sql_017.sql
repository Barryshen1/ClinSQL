WITH male_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 83 AND 93
),
sepsis_patients AS (
    SELECT d.subject_id, d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
    WHERE (LOWER(di.long_title) LIKE '%sepsis%' OR LOWER(di.long_title) LIKE '%septicemia%')
      AND d.subject_id IN (SELECT subject_id FROM male_patients)
),
first_icu_stay AS (
    SELECT 
        i.subject_id, 
        i.hadm_id, 
        i.stay_id, 
        i.intime, 
        i.los,
        ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN sepsis_patients s ON i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
),
first_icu_stay_filtered AS (
    SELECT * FROM first_icu_stay WHERE rn = 1
),
procedure_counts AS (
    SELECT 
        f.stay_id,
        COUNT(DISTINCT p.itemid) AS distinct_procedures
    FROM first_icu_stay_filtered f
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
        ON f.stay_id = p.stay_id
        AND p.starttime >= f.intime
        AND p.starttime <= f.intime + INTERVAL 72 HOUR
    GROUP BY f.stay_id
),
mortality_data AS (
    SELECT 
        a.hadm_id,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN first_icu_stay_filtered f ON a.hadm_id = f.hadm_id
),
combined_data AS (
    SELECT 
        f.stay_id,
        f.hadm_id,
        f.los,
        p.distinct_procedures,
        m.hospital_expire_flag
    FROM first_icu_stay_filtered f
    LEFT JOIN procedure_counts p ON f.stay_id = p.stay_id
    LEFT JOIN mortality_data m ON f.hadm_id = m.hadm_id
),
quartile_data AS (
    SELECT 
        *,
        NTILE(4) OVER (ORDER BY distinct_procedures) AS quartile
    FROM combined_data
)
SELECT 
    quartile,
    AVG(distinct_procedures) AS mean_procedure_count,
    AVG(los) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percent
FROM quartile_data
GROUP BY quartile
ORDER BY quartile;