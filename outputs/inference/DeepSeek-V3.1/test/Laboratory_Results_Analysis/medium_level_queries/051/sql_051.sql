WITH acs_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
        ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
    WHERE pat.gender = 'M'
        AND pat.anchor_age BETWEEN 80 AND 90
        AND (ddiag.icd_code LIKE 'I21%' 
             OR ddiag.icd_code = 'I20.0' 
             OR ddiag.icd_code = 'I24.0')
),
first_troponin AS (
    SELECT 
        acs.subject_id,
        acs.hadm_id,
        le.charttime,
        le.valuenum,
        CASE 
            WHEN le.valuenum <= 14 THEN 'Normal'
            WHEN le.valuenum <= 50 THEN 'Borderline'
            ELSE 'Myocardial Injury'
        END AS category,
        ROW_NUMBER() OVER (PARTITION BY acs.hadm_id ORDER BY le.charttime) AS rn
    FROM acs_admissions acs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON acs.subject_id = le.subject_id AND acs.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 50918  -- High-sensitivity Troponin T
        AND le.valuenum IS NOT NULL
)
SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM first_troponin WHERE rn=1), 2) AS percentage,
    ROUND(AVG(DATE_DIFF(adm.dischtime, adm.admittime, DAY)), 2) AS mean_los_days
FROM first_troponin ft
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ft.hadm_id = adm.hadm_id
WHERE ft.rn = 1
GROUP BY category
ORDER BY category;