WITH cohort AS (
  SELECT p.subject_id, pr.starttime, pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 66 AND 76
  AND LOWER(pr.drug) LIKE '%digoxin%'
)
SELECT AVG(DATE_DIFF(stoptime, starttime, DAY)) AS avg_duration_days
FROM cohort
WHERE stoptime IS NOT NULL;