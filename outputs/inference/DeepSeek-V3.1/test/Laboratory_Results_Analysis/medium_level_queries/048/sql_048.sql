WITH ami_admissions AS (
    SELECT DISTINCT
        adm.subject_id,
        adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
        ON p.subject_id = adm.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 55 AND 65
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%')
),
first_troponin AS (
    SELECT
        ami.subject_id,
        ami.hadm_id,
        le.valuenum AS first_troponin_value,
        ROW_NUMBER() OVER (PARTITION BY ami.hadm_id ORDER BY le.charttime) AS rn
    FROM ami_admissions ami
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON ami.subject_id = le.subject_id AND ami.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003  -- hs-TnT
        AND le.valuenum > 0.01
)
SELECT
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count,
    AVG(first_troponin_value) AS mean_first_troponin,
    APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(50)] AS median_first_troponin,
    APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(25)] AS q1_first_troponin,
    APPROX_QUANTILES(first_troponin_value, 100)[OFFSET(75)] AS q3_first_troponin
FROM first_troponin
WHERE rn = 1;