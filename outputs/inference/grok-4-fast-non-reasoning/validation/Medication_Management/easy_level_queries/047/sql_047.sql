WITH eligible_prescriptions AS (
  SELECT 
    p.subject_id,
    SAFE_CAST(p.dose_val_rx AS FLOAT64) AS numeric_dose,
    p.starttime,
    p.stoptime,
    (DATE(p.stoptime) - DATE(p.starttime)) AS duration_days,
    pat.gender,
    pat.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON 
    pat.subject_id = p.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND (DATE(p.stoptime) - DATE(p.starttime)) >= 0
)

SELECT 
  PERCENTILE_CONT(duration_days, 0.75) - PERCENTILE_CONT(duration_days, 0.25) AS iqr_days
FROM 
  eligible_prescriptions;