SELECT MAX(DATE_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON p.subject_id = pt.subject_id
WHERE pt.gender = 'M'
  AND (EXTRACT(YEAR FROM a.admittime) - (pt.anchor_year - pt.anchor_age)) BETWEEN 82 AND 92
  AND LOWER(p.drug) = 'digoxin'
  AND p.stoptime IS NOT NULL;