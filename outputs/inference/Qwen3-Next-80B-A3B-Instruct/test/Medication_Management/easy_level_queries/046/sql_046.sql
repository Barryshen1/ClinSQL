SELECT PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND LOWER(p.drug) IN ('spironolactone', 'eplerenone')
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
) p
LIMIT 1;