WITH patient_admissions AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 78 AND 88
),
ace_inhibitor_prescriptions AS (
  SELECT pa.subject_id, pa.hadm_id, 
         pr.starttime, pr.stoptime,
         DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON pa.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%ace inhibitor%'
)
SELECT STDDEV(duration_days) AS sd_duration_days
FROM ace_inhibitor_prescriptions;