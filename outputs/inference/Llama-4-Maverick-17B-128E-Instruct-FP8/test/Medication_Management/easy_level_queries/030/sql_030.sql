WITH patient_group AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 42 AND 52
),
amiodarone_prescriptions AS (
  SELECT pg.subject_id, pg.hadm_id, 
         pr.starttime, pr.stoptime,
         DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM patient_group pg
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON pg.subject_id = pr.subject_id AND pg.hadm_id = pr.hadm_id
  WHERE LOWER(pr.drug) LIKE '%amiodarone%'
)
SELECT APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS percentile_25th
FROM amiodarone_prescriptions;