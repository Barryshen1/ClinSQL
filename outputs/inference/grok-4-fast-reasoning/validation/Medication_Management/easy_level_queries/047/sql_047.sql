WITH eligible_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND pr.drug = 'Atorvastatin'
    AND SAFE_CAST(pr.dose_val_rx AS NUMERIC) BETWEEN 40 AND 80
    AND pr.dose_unit_rx = 'MG'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.starttime < pr.stoptime  -- Ensures positive duration
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_days
FROM 
  eligible_prescriptions
WHERE 
  duration_days > 0;