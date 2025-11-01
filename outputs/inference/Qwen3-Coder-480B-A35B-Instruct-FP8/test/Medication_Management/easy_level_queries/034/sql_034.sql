SELECT 
  MAX(DATETIME_DIFF(stoptime, starttime, DAY)) AS longest_prescription_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 51 AND 61
  AND LOWER(p.drug) IN ('hydralazine', 'isosorbide dinitrate')
  AND p.stoptime IS NOT NULL;