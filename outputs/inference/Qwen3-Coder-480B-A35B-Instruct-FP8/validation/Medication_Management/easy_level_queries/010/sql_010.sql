SELECT
  STDDEV_SAMP(DATETIME_DIFF(stoptime, starttime, DAY)) AS stddev_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 73 AND 83
  AND LOWER(pr.drug) LIKE '%nitrate%'
  AND pr.hadm_id IS NOT NULL
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;