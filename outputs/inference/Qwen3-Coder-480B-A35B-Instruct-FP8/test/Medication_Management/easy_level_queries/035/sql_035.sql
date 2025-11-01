SELECT 
  MAX(TIMESTAMP_DIFF(stoptime, starttime, SECOND)) / 3600.0 AS max_duration_hours
FROM 
  physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN 
  physionet-data.mimiciv_3_1_hosp.patients pt
  ON p.subject_id = pt.subject_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 80 AND 90
  AND p.drug IS NOT NULL
  AND REGEXP_CONTAINS(UPPER(p.drug), r'NITRATE|NITROGLYCERIN|ISOSORBIDE')
  AND UPPER(p.route) IN ('IV', 'ORAL', 'SUBLINGUAL')
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;