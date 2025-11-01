SELECT 
  MIN(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS shortest_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON adm.subject_id = p.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pre
  ON adm.hadm_id = pre.hadm_id
WHERE 
  p.gender = 'F'
  AND LOWER(pre.drug) IN ('hydralazine', 'isosorbide dinitrate')
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)
  ) BETWEEN 81 AND 91;