WITH sepsis_admissions AS (
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
        ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
    WHERE pat.gender = 'M'
      AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('99591', '99592', '78552'))
          OR
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'A41%' OR diag.icd_code LIKE 'R65.2%'))
      )
),
lactate_measurements AS (
    SELECT sa.subject_id, sa.hadm_id, le.valuenum AS lactate_value
    FROM sepsis_admissions sa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON sa.subject_id = le.subject_id AND sa.hadm_id = le.hadm_id
    WHERE le.itemid = 50813  -- Lactate
      AND le.valuenum IS NOT NULL
      AND DATE(le.charttime) = DATE(sa.dischtime)
)
SELECT
    APPROX_QUANTILES(lactate_value, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(lactate_value, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(lactate_value, 100)[OFFSET(75)] - APPROX_QUANTILES(lactate_value, 100)[OFFSET(25)] AS iqr
FROM lactate_measurements;