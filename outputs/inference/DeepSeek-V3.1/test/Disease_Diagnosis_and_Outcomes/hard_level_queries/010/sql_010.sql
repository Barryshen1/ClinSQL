WITH cohort AS (
    SELECT 
        p.subject_id,
        p.gender,
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        a.deathtime,
        a.hospital_expire_flag,
        -- Flag for DKA
        MAX(CASE 
            WHEN di.icd_code LIKE '250.1%' AND di.icd_version = 9 THEN 1
            WHEN di.icd_code LIKE 'E1%1%' AND di.icd_version = 10 THEN 1
            ELSE 0 
        END) AS dka_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
    WHERE p.gender = 'M'
        AND p.anchor_age BETWEEN 39 AND 49
    GROUP BY p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
),
complications AS (
    SELECT 
        hadm_id,
        -- Cardiovascular complications: MI, stroke, arrhythmias
        MAX(CASE 
            WHEN icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '427%') THEN 1
            WHEN icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'I48%') THEN 1
            ELSE 0 
        END) AS cardiovascular_complication,
        -- Neurologic complications: stroke, TIA, encephalopathy
        MAX(CASE 
            WHEN icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%' OR icd_code LIKE '348.3%' OR icd_code LIKE '435%') THEN 1
            WHEN icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%' OR icd_code LIKE 'I63%' OR icd_code LIKE 'G93.4%' OR icd_code LIKE 'G45%') THEN 1
            ELSE 0 
        END) AS neurologic_complication
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY hadm_id
)
SELECT 
    c.dka_flag,
    COUNT(*) AS num_patients,
    -- 30-day mortality
    AVG(CASE WHEN a.deathtime <= DATETIME_ADD(a.admittime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS mortality_30d,
    -- Complication rates
    AVG(comp.cardiovascular_complication) AS cardiovascular_complication_rate,
    AVG(comp.neurologic_complication) AS neurologic_complication_rate,
    -- Mean LOS for survivors
    AVG(CASE WHEN a.hospital_expire_flag = 0 THEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) ELSE NULL END) AS mean_survivor_los_days
FROM cohort c
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
LEFT JOIN complications comp
    ON c.hadm_id = comp.hadm_id
GROUP BY c.dka_flag
ORDER BY c.dka_flag;