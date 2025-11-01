SELECT
  AVG(DATETIME_DIFF(stoptime, starttime, DAY)) AS avg_prescription_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 64 AND 74
  AND LOWER(p.drug) IN ('spironolactone', 'eplerenone')
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime >= p.starttime;