WITH sepsis_admissions AS (
    SELECT DISTINCT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE 
        (diag.icd_version = 10 AND diag.icd_code LIKE 'A41%') 
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '038%')
),
first_platelet AS (
    SELECT 
        le.subject_id, 
        le.hadm_id, 
        le.valuenum AS platelet_value
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN sepsis_admissions sa 
        ON le.hadm_id = sa.hadm_id 
        AND le.subject_id = sa.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
        ON le.hadm_id = adm.hadm_id 
        AND le.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON le.subject_id = p.subject_id
    WHERE 
        le.itemid IN (51265, 51237)  -- Platelet count itemids
        AND le.valuenum IS NOT NULL
        AND p.gender = 'M'
        AND le.charttime >= adm.admittime
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY le.hadm_id 
        ORDER BY le.charttime
    ) = 1
)
SELECT 
    STDDEV(platelet_value) AS platelet_std_dev
FROM first_platelet;