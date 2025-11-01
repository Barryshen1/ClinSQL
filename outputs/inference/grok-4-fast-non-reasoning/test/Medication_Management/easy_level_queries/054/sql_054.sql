WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
),
digoxin_prescriptions AS (
  SELECT pr.pharmacy_id,
         (EXTRACT(DAY FROM pr.stoptime - pr.starttime)) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep
    ON pr.subject_id = ep.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT AVG(duration_days) AS avg_duration_days
FROM digoxin_prescriptions;