WITH arb_prescriptions AS (
  SELECT 
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND pr.hadm_id IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
    AND (
      LOWER(pr.drug) LIKE '%losartan%'
      OR LOWER(pr.drug) LIKE '%valsartan%'
      OR LOWER(pr.drug) LIKE '%irbesartan%'
      OR LOWER(pr.drug) LIKE '%candesartan%'
      OR LOWER(pr.drug) LIKE '%telmisartan%'
      OR LOWER(pr.drug) LIKE '%olmesartan%'
      OR LOWER(pr.drug) LIKE '%azilsartan%'
    )
)
SELECT 
  AVG(duration_days) AS avg_duration_days
FROM 
  arb_prescriptions;