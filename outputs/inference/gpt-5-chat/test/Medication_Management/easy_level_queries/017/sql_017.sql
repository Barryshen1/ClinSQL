SELECT
  AVG(TIMESTAMP_DIFF(pres.starttime, pres.stoptime, DAY) * -1) AS avg_warfarin_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON pres.subject_id = pat.subject_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND LOWER(pres.drug) LIKE '%warfarin%'
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL;