SELECT
  MAX(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0) AS max_hosp_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 58 AND 68
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND a.dischtime >= a.admittime;