WITH 
  -- Filter relevant prescriptions
  relevant_prescriptions AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      pr.starttime,
      pr.stoptime,
      pr.drug,
      pr.dose_val_rx,
      pr.form_rx
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
      AND (pr.dose_val_rx BETWEEN 40 AND 80 OR pr.form_rx LIKE '%40 mg%' OR pr.form_rx LIKE '%80 mg%')
  ),
  
  -- Calculate prescription duration
  prescription_durations AS (
    SELECT 
      subject_id,
      TIMESTAMPDIFF(DAY, starttime, stoptime) AS duration_days
    FROM 
      relevant_prescriptions
    WHERE 
      stoptime IS NOT NULL
  )

-- Calculate IQR of prescription durations
SELECT 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_days, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] - APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS IQR
FROM 
  prescription_durations;