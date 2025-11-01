WITH valid_prescriptions AS (
  SELECT 
    p.anchor_age,
    p.gender,
    a.admission_type,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id 
    AND a.hadm_id = pr.hadm_id
  WHERE 
    p.anchor_age BETWEEN 36 AND 46
    AND p.gender = 'M'
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.stoptime > pr.starttime
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0  -- Positive duration
)

SELECT 
  PERCENTILE_CONT(durations, 0.25) OVER() AS q1,
  PERCENTILE_CONT(durations, 0.75) OVER() AS q3,
  (PERCENTILE_CONT(durations, 0.75) OVER() - PERCENTILE_CONT(durations, 0.25) OVER()) AS iqr
FROM (
  SELECT duration_days AS durations
  FROM valid_prescriptions
)
LIMIT 1;