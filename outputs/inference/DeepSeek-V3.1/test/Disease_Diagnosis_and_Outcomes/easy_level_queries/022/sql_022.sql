WITH stroke_admissions AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND di.seq_num = 1  -- primary diagnosis
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'I63%') OR
      (di.icd_version = 9 AND (di.icd_code LIKE '433%' OR di.icd_code LIKE '434%' OR di.icd_code LIKE '436%'))
    )
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(los, 100) [OFFSET(25)] AS q1,
  APPROX_QUANTILES(los, 100) [OFFSET(75)] AS q3,
  APPROX_QUANTILES(los, 100) [OFFSET(75)] - APPROX_QUANTILES(los, 100) [OFFSET(25)] AS iqr
FROM stroke_admissions;