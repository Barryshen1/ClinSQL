SELECT
  AVG(DATETIME_DIFF(stoptime, starttime, DAY)) AS avg_warfarin_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE
  LOWER(pr.drug) = 'warfarin'
  AND pt.gender = 'M'
  AND pt.anchor_age BETWEEN 43 AND 53
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL;