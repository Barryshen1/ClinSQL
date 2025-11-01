WITH amiodarone_prescriptions AS (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    p.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND LOWER(p.drug) LIKE '%amiodarone%'
    AND p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime
    AND TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) >= 0  -- Ensure non-negative
)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr_duration_days
FROM 
  amiodarone_prescriptions;