SELECT
  APPROX_QUANTILES(
    DATETIME_DIFF(stoptime, starttime, DAY), 100
  )[OFFSET(75)] AS percentile_75_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
USING
  (subject_id)
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 38 AND 48
  AND pr.drug LIKE '%artan%'
  AND pr.hadm_id IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;