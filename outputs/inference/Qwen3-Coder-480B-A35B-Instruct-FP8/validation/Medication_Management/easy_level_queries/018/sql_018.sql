SELECT 
  MAX(DATETIME_DIFF(stoptime, starttime, DAY)) AS longest_digoxin_prescription_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE 
  LOWER(p.drug) LIKE '%digoxin%'
  AND pat.gender = 'M'
  AND pat.anchor_age BETWEEN 82 AND 92
  AND p.stoptime IS NOT NULL;