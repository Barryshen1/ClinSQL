SELECT AVG(DATE_DIFF(stoptime, starttime, DAY)) AS average_duration
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 64 AND 74
  AND (LOWER(p.drug) = 'spironolactone' OR LOWER(p.drug) = 'eplerenone')
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;