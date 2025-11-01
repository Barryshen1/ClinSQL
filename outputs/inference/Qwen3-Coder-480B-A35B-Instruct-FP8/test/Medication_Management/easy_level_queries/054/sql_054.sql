SELECT 
  AVG(DATE_DIFF(stoptime, starttime, DAY)) AS avg_digoxin_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON pr.subject_id = pt.subject_id
WHERE 
  LOWER(pr.drug) = 'digoxin'
  AND pt.gender = 'M'
  AND pt.anchor_age BETWEEN 66 AND 76
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;