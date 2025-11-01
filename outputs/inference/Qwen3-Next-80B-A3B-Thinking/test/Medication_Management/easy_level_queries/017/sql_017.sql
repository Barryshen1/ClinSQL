SELECT AVG(TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY)) AS avg_duration
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND (pt.anchor_age + (EXTRACT(YEAR FROM a.admittime) - pt.anchor_year)) BETWEEN 43 AND 53
  AND (LOWER(p.drug) LIKE '%warfarin%' OR LOWER(p.drug) LIKE '%coumadin%')
  AND p.stoptime IS NOT NULL
  AND p.stoptime > p.starttime;