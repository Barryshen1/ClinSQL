WITH cohort AS (
    SELECT 
        p.subject_id, 
        a.hadm_id, 
        a.hospital_expire_flag,
        FIRST_TROP.valuenum AS first_troponin
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id
    INNER JOIN (
        SELECT 
            le.subject_id, 
            le.hadm_id, 
            le.valuenum,
            ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
        WHERE le.itemid = 50918  -- hs-Troponin T
        AND le.valuenum > 14     -- exceeding 99th percentile
    ) FIRST_TROP
        ON a.hadm_id = FIRST_TROP.hadm_id AND FIRST_TROP.rn = 1
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 64 AND 74
        AND d.icd_code = 'R079'   -- Chest pain, unspecified (ICD-10)
        AND d.icd_version = 10
)
SELECT 
    COUNT(*) AS n_patients,
    AVG(first_troponin) AS mean_first_troponin,
    STDDEV(first_troponin) AS std_first_troponin,
    MIN(first_troponin) AS min_first_troponin,
    MAX(first_troponin) AS max_first_troponin,
    SUM(hospital_expire_flag) AS n_died,
    ROUND(SUM(hospital_expire_flag) / COUNT(*) * 100, 2) AS mortality_rate_percent
FROM cohort;