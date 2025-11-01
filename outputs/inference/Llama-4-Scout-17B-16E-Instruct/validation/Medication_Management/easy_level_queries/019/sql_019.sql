WITH patient_demographics AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 58 AND 68
),
prescription_durations AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  JOIN 
    patient_demographics p 
      ON pr.subject_id = p.subject_id
  WHERE 
    LOWER(pr.drug) IN ('heparin', 'enoxaparin')
    AND pr.stoptime IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(duration, 1000)[500] AS median_duration
FROM 
  prescription_durations;