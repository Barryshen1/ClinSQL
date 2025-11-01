SELECT 
  MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
ON 
  p.subject_id = a.subject_id
WHERE 
  p.gender = 'M'
  AND p.anchor_age BETWEEN 58 AND 68
  AND a.dischtime IS NOT NULL;