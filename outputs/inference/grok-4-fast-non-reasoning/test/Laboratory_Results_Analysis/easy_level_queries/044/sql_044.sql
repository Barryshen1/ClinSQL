WITH stroke_admissions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    a.hadm_id = d.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
  ON 
    d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age = 94
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'
    AND a.dischtime IS NOT NULL
),
glucose_values AS (
  SELECT 
    le.valuenum
  FROM 
    stroke_admissions sa
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON 
    sa.hadm_id = le.hadm_id
  WHERE 
    le.itemid = 225624  -- Serum glucose
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND DATE(le.charttime) = DATE(sa.dischtime)
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  (APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)]) AS iqr
FROM 
  glucose_values;