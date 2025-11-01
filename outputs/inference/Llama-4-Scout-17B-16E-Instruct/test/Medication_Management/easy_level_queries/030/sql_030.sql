WITH 
  -- Filter for amiodarone prescriptions in females aged 42-52
  amiodarone_prescriptions AS (
    SELECT 
      p.subject_id,
      pr.starttime,
      pr.stoptime,
      TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    JOIN 
      `physionet-data.mimiciv_3_1_hosp`.patients p 
        ON pr.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 42 AND 52
      AND LOWER(pr.drug) LIKE '%amiodarone%'
      AND pr.stoptime IS NOT NULL
  )

-- Calculate 25th percentile duration
SELECT 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS percentile_25
FROM 
  amiodarone_prescriptions;