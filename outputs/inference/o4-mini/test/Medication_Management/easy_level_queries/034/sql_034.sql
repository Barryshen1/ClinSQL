SELECT
  MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS max_prescription_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  AND p.hadm_id    = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 51 AND 61
  AND (
    LOWER(p.drug) LIKE '%hydralazine%'
    OR LOWER(p.drug) LIKE '%isosorbide dinitrate%'
  )
  AND p.starttime IS NOT NULL
  AND p.stoptime  IS NOT NULL
  AND p.starttime >= a.admittime
  AND p.stoptime  <= a.dischtime;