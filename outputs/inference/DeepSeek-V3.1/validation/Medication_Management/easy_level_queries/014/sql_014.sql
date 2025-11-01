SELECT
  MIN(DATE_DIFF(stoptime, starttime, DAY)) AS min_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.hadm_id = a.hadm_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 86 AND 96
  AND LOWER(p.drug) LIKE '%atorvastatin%'
  AND LOWER(p.dose_unit_rx) = 'mg'
  AND SAFE_CAST(p.dose_val_rx AS NUMERIC) BETWEEN 40 AND 80
  AND p.stoptime IS NOT NULL;