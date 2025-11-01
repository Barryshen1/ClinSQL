WITH atorvastatin_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
)
SELECT 
  APPROX_QUANTILES(DATE_DIFF(stoptime, starttime, DAY), 100)[OFFSET(75)] - 
  APPROX_QUANTILES(DATE_DIFF(stoptime, starttime, DAY), 100)[OFFSET(25)] AS IQR_days
FROM 
  atorvastatin_prescriptions;