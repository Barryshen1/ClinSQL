SELECT 
  MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS max_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pat
ON 
  p.subject_id = pat.subject_id
WHERE 
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 80 AND 90
  AND (
    LOWER(p.drug) LIKE '%nitroglycerin%' 
    OR LOWER(p.drug) LIKE '%isosorbide%'
  )
  AND (
    LOWER(p.route) LIKE '%iv%' 
    OR LOWER(p.route) = 'po' 
    OR LOWER(p.route) = 'sl'
  )
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;