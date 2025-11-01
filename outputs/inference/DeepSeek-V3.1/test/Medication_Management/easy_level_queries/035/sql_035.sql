SELECT 
  MAX(DATE_DIFF(stoptime, starttime, HOUR)) AS max_duration_hours
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` pt 
  ON pr.subject_id = pt.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` adm 
  ON pr.hadm_id = adm.hadm_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 80 AND 90
  AND LOWER(pr.drug) LIKE '%nitrate%'
  AND REGEXP_CONTAINS(LOWER(pr.route), r'iv|po|sl|oral|sublingual')
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime > pr.starttime;