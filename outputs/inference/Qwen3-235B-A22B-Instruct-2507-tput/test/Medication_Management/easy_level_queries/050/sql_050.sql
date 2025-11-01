SELECT 
  AVG(DATETIME_DIFF(stoptime, starttime, HOUR)) AS avg_duration_hours
FROM 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON a.subject_id = pat.subject_id
WHERE 
  pat.gender = 'M'
  AND LOWER(p.drug) LIKE '%spironolactone%'
     OR LOWER(p.drug) LIKE '%eplerenone%'
  AND (EXTRACT(YEAR FROM a.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 64 AND 74
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;