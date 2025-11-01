SELECT
  AVG(DATETIME_DIFF(stoptime, starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pt
ON
  p.subject_id = pt.subject_id
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 43 AND 53
  AND LOWER(p.drug) LIKE '%warfarin%'
  AND p.stoptime IS NOT NULL;