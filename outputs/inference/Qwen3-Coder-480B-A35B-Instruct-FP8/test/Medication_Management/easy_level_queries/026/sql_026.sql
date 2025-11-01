SELECT
  APPROX_QUANTILES(
    DATE_DIFF(stoptime, starttime, DAY), 100
  )[OFFSET(25)] AS percentile_25_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE
  LOWER(p.drug) LIKE '%dihydropyridine%ccb%'
  AND pt.gender = 'F'
  AND pt.anchor_age BETWEEN 81 AND 91
  AND p.stoptime IS NOT NULL;