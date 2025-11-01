SELECT PERCENTILE_CONT(duration, 0.5) OVER () AS median_duration
FROM (
  SELECT TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'M'
    AND pt.anchor_age BETWEEN 90 AND 100
    AND LOWER(p.drug) IN ('spironolactone', 'eplerenone')
    AND p.stoptime IS NOT NULL
) AS durations
LIMIT 1;