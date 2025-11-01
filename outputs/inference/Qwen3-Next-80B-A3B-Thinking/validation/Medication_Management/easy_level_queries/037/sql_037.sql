SELECT PERCENTILE_CONT(duration, 0.25) OVER () AS percentile_25
FROM (
  SELECT DATE_DIFF(stoptime, starttime, DAY) AS duration
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age = 55
    AND LOWER(p.drug) LIKE '%pril%'
    AND p.stoptime IS NOT NULL
) AS subquery
LIMIT 1;