WITH cohort AS (
    SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
),
ami_admissions AS (
    SELECT cohort.*
    FROM cohort
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON cohort.subject_id = di.subject_id AND cohort.hadm_id = di.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
    WHERE di.seq_num = 1
        AND (dd.icd_code LIKE 'I21%' OR dd.icd_code LIKE 'I22%')
),
first_troponin AS (
    SELECT 
        aa.subject_id, 
        aa.hadm_id, 
        le.charttime, 
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) AS rn
    FROM ami_admissions aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON aa.subject_id = le.subject_id AND aa.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 51003  -- Troponin T
        AND le.valuenum IS NOT NULL
        AND le.valueuom = 'ng/mL'
)
SELECT 
    CASE 
        WHEN valuenum <= 0.01 THEN 'Normal'
        WHEN valuenum > 0.01 AND valuenum <= 0.1 THEN 'Borderline'
        WHEN valuenum > 0.1 THEN 'Elevated'
    END AS category,
    COUNT(*) AS count
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;