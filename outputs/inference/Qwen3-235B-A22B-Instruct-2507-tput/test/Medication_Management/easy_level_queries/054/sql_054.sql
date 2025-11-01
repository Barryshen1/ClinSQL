SELECT 
  AVG(DATETIME_DIFF(stoptime, starttime, SECOND) / (24 * 3600.0)) AS avg_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON p.subject_id = pat.subject_id
WHERE 
  LOWER(p.drug) = 'digoxin'
  AND pat.gender = 'M'
  AND pat.anchor_age BETWEEN 66 AND 76
  AND p.stoptime IS NOT NULL
  AND p.starttime IS NOT NULL
  AND p.stoptime >= p.starttime;