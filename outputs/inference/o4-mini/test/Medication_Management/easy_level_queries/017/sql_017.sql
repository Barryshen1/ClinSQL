SELECT
  AVG(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_warfarin_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON a.subject_id = pr.subject_id
   AND a.hadm_id    = pr.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 43 AND 53
  AND LOWER(pr.drug) LIKE '%warfarin%'
  AND pr.starttime IS NOT NULL
  AND pr.stoptime  IS NOT NULL
  AND pr.stoptime  >= pr.starttime;