WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
  AND anchor_age BETWEEN 86 AND 96
),
atorvastatin_prescriptions AS (
  SELECT p.subject_id, pr.starttime, pr.stoptime,
         CAST(REGEXP_EXTRACT(pr.drug, r'\d+') AS INT64) AS dose
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN eligible_patients p ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
  AND CAST(REGEXP_EXTRACT(pr.dose_val_rx, r'\d+') AS INT64) BETWEEN 40 AND 80
)
SELECT MIN(DATE_DIFF(stoptime, starttime, DAY)) AS min_duration_days
FROM atorvastatin_prescriptions;