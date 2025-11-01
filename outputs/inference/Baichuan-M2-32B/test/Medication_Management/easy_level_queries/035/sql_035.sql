SELECT MAX(duration_hours) AS max_duration_hours
FROM (
  SELECT 
    TIMESTAMP_DIFF(p.stoptime, p.starttime, HOUR) AS duration_hours
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt 
    ON p.subject_id = pt.subject_id
  WHERE 
    pt.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - (pt.anchor_year - pt.anchor_age)) BETWEEN 80 AND 90
    AND (LOWER(p.drug) LIKE '%nitrate%' 
         OR LOWER(p.drug) LIKE '%nitroglycerin%' 
         OR LOWER(p.drug) LIKE '%isosorbide dinitrate%')
    AND p.route IN ('IV', 'oral', 'sublingual')
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
);