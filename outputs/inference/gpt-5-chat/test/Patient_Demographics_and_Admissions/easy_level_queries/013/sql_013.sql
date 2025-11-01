SELECT 
  MAX(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS max_hosp_los_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 58 AND 68
  AND a.dischtime IS NOT NULL;