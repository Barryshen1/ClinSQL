SELECT
  APPROX_QUANTILES(DATETIME_DIFF(stoptime, starttime, DAY), 2)[OFFSET(1)] AS median_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 58 AND 68
  AND (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND stoptime > starttime;