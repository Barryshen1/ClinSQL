WITH arb_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 77 AND 87
    AND pr.hadm_id IS NOT NULL
    AND (LOWER(pr.drug) LIKE '%losartan%' 
         OR LOWER(pr.drug) LIKE '%valsartan%' 
         OR LOWER(pr.drug) LIKE '%candesartan%' 
         OR LOWER(pr.drug) LIKE '%irbesartan%' 
         OR LOWER(pr.drug) LIKE '%olmesartan%' 
         OR LOWER(pr.drug) LIKE '%telmisartan%' 
         OR LOWER(pr.drug) LIKE '%eprosartan%')
),
prescription_durations AS (
  SELECT 
    subject_id,
    drug,
    DATETIME_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM 
    arb_prescriptions
  WHERE 
    starttime IS NOT NULL AND stoptime IS NOT NULL
)

SELECT 
  AVG(duration_days) AS avg_duration_days
FROM 
  prescription_durations;