WITH patient_age AS (
  SELECT p.subject_id, p.gender, a.admittime, 
         p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
prescription_durations AS (
  SELECT pa.subject_id, pr.starttime, pr.stoptime, 
         DATETIME_DIFF(pr.stoptime, pr.starttime, MINUTE) AS duration_minutes
  FROM patient_age pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pa.subject_id = pr.subject_id
  WHERE pa.gender = 'M' AND pa.age_at_admission BETWEEN 64 AND 74
  AND LOWER(pr.drug) LIKE '%spironolactone%' OR LOWER(pr.drug) LIKE '%eplerenone%'
)
SELECT AVG(duration_minutes) AS average_duration_minutes
FROM prescription_durations;