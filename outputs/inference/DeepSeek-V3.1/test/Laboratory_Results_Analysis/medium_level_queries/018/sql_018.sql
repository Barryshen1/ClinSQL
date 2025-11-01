WITH acs_patients AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id,
        adm.admittime,
        adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON pt.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
        ON diag.icd_code = ddiag.icd_code AND diag.icd_version = ddiag.icd_version
    WHERE pt.gender = 'M'
        AND pt.anchor_age BETWEEN 90 AND 100
        AND (ddiag.icd_code LIKE 'I21%' OR ddiag.icd_code = 'I20.0')
),
first_troponin AS (
    SELECT
        acs.subject_id,
        acs.hadm_id,
        le.charttime,
        le.valuenum AS troponin_value,
        CASE
            WHEN le.valuenum < 0.01 THEN 'Normal'
            WHEN le.valuenum BETWEEN 0.01 AND 0.1 THEN 'Borderline'
            WHEN le.valuenum > 0.1 THEN 'Elevated'
            ELSE 'Unknown'
        END AS troponin_category,
        ROW_NUMBER() OVER (PARTITION BY acs.hadm_id ORDER BY le.charttime) AS rn
    FROM acs_patients acs
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON acs.hadm_id = le.hadm_id
    WHERE le.itemid = 51003  -- Troponin T
        AND le.valuenum IS NOT NULL
)
SELECT
    troponin_category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
    ROUND(AVG(DATE_DIFF(acs.dischtime, acs.admittime, DAY)), 2) AS mean_los
FROM acs_patients acs
INNER JOIN first_troponin ft
    ON acs.hadm_id = ft.hadm_id
WHERE ft.rn = 1  -- Ensure first troponin per admission
GROUP BY troponin_category
ORDER BY troponin_category;