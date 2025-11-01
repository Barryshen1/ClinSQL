WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),
relevant_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN eligible_patients p ON a.subject_id = p.subject_id
),
medicated_admissions AS (
  SELECT DISTINCT r.hadm_id, r.admittime, r.dischtime
  FROM relevant_admissions r
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON r.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%hydralazine%' OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
)
SELECT MIN(DATE_DIFF(dischtime, admittime, DAY)) AS shortest_duration_days
FROM medicated_admissions;