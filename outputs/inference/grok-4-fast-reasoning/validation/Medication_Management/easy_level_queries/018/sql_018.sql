SELECT
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS longest_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON
  pres.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  pres.subject_id = a.subject_id
  AND pres.hadm_id = a.hadm_id
WHERE
  p.gender = 'M'
  AND LOWER(pres.drug) LIKE '%digoxin%'
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND DATE_DIFF(pres.stoptime, pres.starttime, DAY) > 0
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
  ) BETWEEN 82 AND 92;