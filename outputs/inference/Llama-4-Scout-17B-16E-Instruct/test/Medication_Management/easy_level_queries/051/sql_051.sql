WITH 
  -- Filter patients and prescriptions for males aged 86-96 and digoxin prescriptions
  eligible_prescriptions AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      pr.starttime,
      pr.stoptime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON 
      p.subject_id = pr.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 86 AND 96
      AND LOWER(pr.drug) LIKE '%digoxin%'
  ),
  
  -- Calculate prescription duration in days
  prescription_durations AS (
    SELECT 
      subject_id,
      anchor_age,
      DATE_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM 
      eligible_prescriptions
  )

-- Calculate IQR of prescription durations
SELECT 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_days, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] - 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS IQR
FROM 
  prescription_durations;