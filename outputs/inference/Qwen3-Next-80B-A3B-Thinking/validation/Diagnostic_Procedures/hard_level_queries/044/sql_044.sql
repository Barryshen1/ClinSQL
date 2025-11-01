WITH patients_with_cardiogenic_shock AS (
    SELECT DISTINCT
        p.subject_id,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code 
        AND d.icd_version = d_icd.icd_version
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 82 AND 92
        AND d_icd.long_title LIKE '%cardiogenic shock%'
),

icu_stays AS (
    SELECT 
        i.stay_id,
        i.hadm_id,
        i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN patients_with_cardiogenic_shock p 
        ON i.hadm_id = p.hadm_id
),

procedure_counts AS (
    SELECT 
        i.stay_id,
        COUNT(pe.itemid) AS procedure_count
    FROM icu_stays i
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
        ON i.stay_id = pe.stay_id
        AND pe.starttime >= i.intime
        AND pe.starttime <= i.intime + INTERVAL '24' HOUR
    GROUP BY i.stay_id
),

main_data AS (
    SELECT 
        p.subject_id,
        p.hadm_id,
        p.hospital_expire_flag,
        DATE_DIFF(p.dischtime, p.admittime, DAY) AS hospital_los_days,
        COALESCE(pc.procedure_count, 0) AS procedure_count
    FROM patients_with_cardiogenic_shock p
    JOIN icu_stays i ON p.hadm_id = i.hadm_id
    LEFT JOIN procedure_counts pc ON i.stay_id = pc.stay_id
)

SELECT 
    quintile,
    AVG(procedure_count) AS mean_procedure_count,
    AVG(hospital_los_days) AS mean_los_days,
    AVG(hospital_expire_flag) * 100 AS mortality_percentage
FROM (
    SELECT 
        procedure_count,
        hospital_los_days,
        hospital_expire_flag,
        NTILE(5) OVER (ORDER BY procedure_count) AS quintile
    FROM main_data
) AS quintile_data
GROUP BY quintile
ORDER BY quintile;