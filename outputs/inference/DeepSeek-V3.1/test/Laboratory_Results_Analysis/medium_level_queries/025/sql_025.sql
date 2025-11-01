WITH first_troponin AS (
    SELECT 
        le.subject_id,
        le.valuenum AS troponin_value
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON adm.subject_id = le.subject_id AND adm.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE p.anchor_age BETWEEN 58 AND 68
        AND p.gender = 'F'
        AND (diag.icd_code LIKE 'R07.9' OR diag.icd_code LIKE 'I21%')
        AND diag.icd_version = 10
        AND le.itemid = 51003  -- Troponin T quantitative
        AND le.valuenum > 0.01
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY p.subject_id 
        ORDER BY le.charttime
    ) = 1
)
SELECT 
    COUNT(*) AS n_patients,
    AVG(troponin_value) AS mean_troponin,
    STDDEV(troponin_value) AS sd_troponin,
    MIN(troponin_value) AS min_troponin,
    MAX(troponin_value) AS max_troponin
FROM first_troponin;