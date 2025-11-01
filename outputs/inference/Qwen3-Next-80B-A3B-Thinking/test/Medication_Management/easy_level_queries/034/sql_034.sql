SELECT MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'F'
  AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 51 AND 61
  AND (LOWER(p.drug) LIKE '%hydralazine%' OR LOWER(p.drug) LIKE '%isosorbide dinitrate%')
  AND stoptime >= starttime;