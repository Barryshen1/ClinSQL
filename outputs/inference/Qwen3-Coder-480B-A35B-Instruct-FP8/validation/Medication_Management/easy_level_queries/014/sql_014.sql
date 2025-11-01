SELECT
  MIN(DATETIME_DIFF(stoptime, starttime, DAY)) AS min_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 86 AND 96
  AND LOWER(pr.drug) LIKE '%atorvastatin%'
  AND pr.dose_unit_rx = 'mg'
  AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime > pr.starttime;