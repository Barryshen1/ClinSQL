SELECT
  AVG(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY)) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON p.subject_id = pr.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON pr.hadm_id = a.hadm_id
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 64 AND 74
  AND a.admission_type != 'OBSERVATION'
  AND pr.drug IN ('Spironolactone', 'Eplerenone')
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime > pr.starttime;