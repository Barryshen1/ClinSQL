SELECT
  APPROX_QUANTILES(DATETIME_DIFF(stoptime, starttime, DAY), 100)[OFFSET(25)] AS percentile_25_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` ad
  ON pr.hadm_id = ad.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON ad.subject_id = pt.subject_id
WHERE
  pt.anchor_age BETWEEN 76 AND 86
  AND pt.gender = 'M'
  AND LOWER(pr.drug) LIKE '%nitrate%'
  AND pr.route IN ('IV', 'oral')
  AND pr.stoptime IS NOT NULL
  AND pr.starttime IS NOT NULL;