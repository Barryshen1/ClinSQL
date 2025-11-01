SELECT
  STDDEV_SAMP(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS sd_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
ON
  pres.subject_id = pat.subject_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND DATETIME_DIFF(pres.stoptime, pres.starttime, DAY) >= 0
  AND LOWER(pres.drug) LIKE '%pril%';