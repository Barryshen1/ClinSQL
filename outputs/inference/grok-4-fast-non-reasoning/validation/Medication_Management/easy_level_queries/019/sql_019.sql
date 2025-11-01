WITH heparin_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.starttime,
    p.stoptime,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    p.subject_id = pat.subject_id
  WHERE 
    (LOWER(p.drug) LIKE '%heparin%' 
     OR LOWER(p.drug) LIKE '%enoxaparin%')
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) >= 0
)
SELECT 
  PERCENTILE_CONT(0.5) OVER (ORDER BY duration_days) AS median_duration_days
FROM 
  heparin_prescriptions;