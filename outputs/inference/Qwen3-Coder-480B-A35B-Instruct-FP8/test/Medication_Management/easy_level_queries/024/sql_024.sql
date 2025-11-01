SELECT 
  MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_dapt_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE 
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 84 AND 94
  AND p.drug IS NOT NULL
  AND LOWER(p.drug) IN (
    'clopidogrel',
    'prasugrel',
    'ticagrelor'
  )
  AND p.hadm_id IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;