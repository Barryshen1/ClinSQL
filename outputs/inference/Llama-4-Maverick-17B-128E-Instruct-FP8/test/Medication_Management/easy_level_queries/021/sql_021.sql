WITH atorvastatin_prescriptions AS (
  SELECT p.subject_id, pr.hadm_id, pr.starttime, pr.stoptime,
         TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 75 AND 85
    AND LOWER(pr.drug) LIKE '%atorvastatin%' 
    AND pr.dose_unit_rx = 'mg'
    AND CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
)
SELECT 
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS IQR
FROM atorvastatin_prescriptions;