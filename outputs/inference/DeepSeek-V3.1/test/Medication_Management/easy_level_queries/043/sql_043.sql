SELECT
  MIN(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS shortest_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON a.hadm_id = pr.hadm_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 81 AND 91
  AND LOWER(pr.drug) LIKE '%hydralazine%' OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%';