WITH stroke_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pt
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pt.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pt.gender = 'F' 
    AND pt.anchor_age = 87
    AND (
      (diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('430', '431', '432'))
      OR 
      (diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I60', 'I61', 'I62'))
    )
),
platelet_values AS (
  SELECT 
    lab.valuenum
  FROM stroke_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.subject_id = lab.subject_id
    AND c.hadm_id = lab.hadm_id
  WHERE 
    lab.itemid = 51265  -- Platelet Count
    AND lab.valuenum IS NOT NULL
    AND DATE(lab.charttime) = DATE(c.dischtime)
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS platelet_75th_percentile
FROM platelet_values;