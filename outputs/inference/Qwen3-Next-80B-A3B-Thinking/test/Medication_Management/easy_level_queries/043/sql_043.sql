SELECT MIN(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS shortest_duration
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON a.subject_id = pr.subject_id
  AND a.hadm_id = pr.hadm_id
WHERE p.gender = 'F'
  AND (p.anchor_age + DATE_DIFF(a.admittime, DATE(p.anchor_year, 1, 1), YEAR)) BETWEEN 81 AND 91
  AND (LOWER(pr.drug) LIKE '%hydralazine%' OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%')
  AND a.dischtime IS NOT NULL;