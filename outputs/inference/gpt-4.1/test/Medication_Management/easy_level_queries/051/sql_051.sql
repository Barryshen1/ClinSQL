WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),
digoxin_prescriptions AS (
  SELECT pr.subject_id,
         pr.hadm_id,
         pr.starttime,
         pr.stoptime,
         TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN eligible_patients ep
    ON pr.subject_id = ep.subject_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS duration_days_p25,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS duration_days_p75
FROM digoxin_prescriptions;