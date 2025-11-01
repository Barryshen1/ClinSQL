WITH stroke_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.seq_num = '1'
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'I63%'
)
SELECT 
  PERCENTILE_CONT(0.25, los) OVER() AS q1_los,
  PERCENTILE_CONT(0.75, los) OVER() AS q3_los,
  PERCENTILE_CONT(0.75, los) OVER() - PERCENTILE_CONT(0.25, los) OVER() AS iqr_los,
  COUNT(*) AS num_admissions
FROM stroke_patients
WHERE los >= 0  -- Exclude any negative LOS (rare data errors)
;