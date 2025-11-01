WITH digoxin_prescriptions AS (
  SELECT 
    p.anchor_age,
    p.gender,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE 
    LOWER(pr.drug) LIKE '%digoxin%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr_days
FROM 
  digoxin_prescriptions;