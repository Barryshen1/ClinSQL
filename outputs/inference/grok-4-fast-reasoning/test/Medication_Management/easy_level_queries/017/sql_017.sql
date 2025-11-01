SELECT
  AVG(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS avg_warfarin_duration_days
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
  AND pat.anchor_age BETWEEN 43 AND 53
  AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
  AND LOWER(p.drug) LIKE '%warfarin%'
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;