WITH inpatient_arbs AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'NEWBORN', 'URGENT')
    AND pr.stoptime IS NOT NULL
    AND DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) >= 0
    AND (
      LOWER(pr.drug) LIKE '%losartan%' OR
      LOWER(pr.drug) LIKE '%valsartan%' OR
      LOWER(pr.drug) LIKE '%candesartan%' OR
      LOWER(pr.drug) LIKE '%irbesartan%' OR
      LOWER(pr.drug) LIKE '%telmisartan%' OR
      LOWER(pr.drug) LIKE '%olmesartan%' OR
      LOWER(pr.drug) LIKE '%azilsartan%'
    )
),
patient_totals AS (
  SELECT 
    subject_id,
    SUM(duration_days) AS total_arb_days
  FROM 
    inpatient_arbs
  GROUP BY 
    subject_id
  HAVING 
    total_arb_days > 0
)
SELECT 
  PERCENTILE_CONT(0.75) OVER() AS p75_total_arb_days
FROM 
  patient_totals;