SELECT
  AVG(DATE_DIFF(CAST(p.stoptime AS DATE), CAST(p.starttime AS DATE), DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pa
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
ON
  pa.subject_id = p.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON
  p.hadm_id = a.hadm_id
WHERE
  pa.gender = 'F'
  AND pa.anchor_age BETWEEN 77 AND 87
  AND LOWER(p.drug) LIKE '%sartan%'
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime
  AND p.starttime >= a.admittime
  AND p.stoptime <= a.dischtime;