SELECT
  AVG(DATE_DIFF(p.stoptime, p.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON
  p.subject_id = pat.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.hadm_id = a.hadm_id
WHERE
  pat.gender = 'M'
  AND LOWER(p.drug) LIKE '%digoxin%'
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.hadm_id IS NOT NULL
  AND (
    pat.anchor_age + EXTRACT(YEAR FROM a.admittime) - pat.anchor_year
  ) BETWEEN 66 AND 76;