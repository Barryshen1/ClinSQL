SELECT 
  MAX((UNIX_SECONDS(CAST(a.dischtime AS TIMESTAMP)) - UNIX_SECONDS(CAST(a.admittime AS TIMESTAMP))) / (24 * 60 * 60.0)) AS max_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
WHERE 
  p.gender = 'M'
  AND a.dischtime IS NOT NULL
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68;