WITH dapt_prescriptions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
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
    ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_type IN ('ADMITTED', 'EMERGENCY', 'URGENT')
    AND (LOWER(pr.drug) LIKE '%aspirin%' 
         OR LOWER(pr.drug) LIKE '%clopidogrel%')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) > 0
),
admission_dapt AS (
  SELECT 
    hadm_id,
    -- For simplicity, take MIN duration per admission (earliest order); could AVG if multiple
    MIN(duration_days) AS dapt_duration
  FROM (
    SELECT 
      hadm_id,
      duration_days,
      COUNT(DISTINCT drug) OVER (PARTITION BY hadm_id) AS dapt_drug_count
    FROM dapt_prescriptions
  )
  WHERE dapt_drug_count <= 2  -- Single DAPT regimen
  GROUP BY hadm_id
  HAVING dapt_duration IS NOT NULL
)
SELECT 
  q3 - q1 AS iqr
FROM (
  SELECT 
    PERCENTILE_CONT(dapt_duration, 0.25) OVER() AS q1,
    PERCENTILE_CONT(dapt_duration, 0.75) OVER() AS q3
  FROM admission_dapt
);