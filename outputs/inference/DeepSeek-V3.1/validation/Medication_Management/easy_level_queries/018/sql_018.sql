SELECT
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pt
  ON p.subject_id = pt.subject_id
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 82 AND 92
  AND LOWER(p.drug) LIKE '%digoxin%'
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;