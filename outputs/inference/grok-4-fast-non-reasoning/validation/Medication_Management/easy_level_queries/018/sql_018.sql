WITH eligible_orders AS (
  SELECT 
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.drug IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
)
SELECT 
  MAX(duration_days) AS longest_digoxin_prescription_days
FROM eligible_orders;