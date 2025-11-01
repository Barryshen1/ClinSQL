SELECT 
  MAX(TIMESTAMP_DIFF(p.stoptime, p.starttime, MINUTE) / 60.0) AS max_duration_hours
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.hadm_id = a.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON p.subject_id = pat.subject_id
WHERE 
  pat.gender = 'F'
  AND (EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 80 AND 90
  AND (
    LOWER(p.drug) LIKE '%nitrate%' 
    OR LOWER(p.drug) LIKE '%nitroglycerin%' 
    OR LOWER(p.drug) LIKE '%isosorbide%'
  )
  AND LOWER(p.route) IN (
    'iv', 'intravenous', 
    'po', 'oral', 
    'sl', 'sublingual', 'sub lingual', 'sub-lingual'
  )
  AND p.stoptime IS NOT NULL
  AND p.starttime <= p.stoptime;