WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age, a.admittime,
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age = 87
),
digoxin_prescriptions AS (
  SELECT pa.subject_id, pa.hadm_id, pr.starttime, pr.stoptime,
         DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pa.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
)
SELECT MAX(duration_days) AS longest_duration
FROM digoxin_prescriptions;