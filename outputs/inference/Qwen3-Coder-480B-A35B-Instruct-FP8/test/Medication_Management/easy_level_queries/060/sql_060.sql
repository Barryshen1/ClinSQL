SELECT 
  MAX(DATETIME_DIFF(stoptime, starttime, DAY)) AS longest_ace_inhibitor_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 38 AND 48
  AND pr.drug LIKE '%ACE inhibitor%'
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL;