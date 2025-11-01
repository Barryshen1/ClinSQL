WITH 
-- Calculate medication complexity score
medication_complexity AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT CASE WHEN pr.drug_type = 'medication' THEN pr.drug END) AS unique_drugs,
    COUNT(DISTINCT CASE WHEN pr.drug_type = 'medication' AND pr.route IN ('IV', 'PO') THEN pr.drug END) * 2 AS high_risk_drugs,
    COUNT(DISTINCT pr.route) AS routes
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.patients p ON pr.subject_id = p.subject_id
  GROUP BY 
    p.subject_id
),

-- Calculate medication complexity score for each patient
complexity_score AS (
  SELECT 
    subject_id,
    unique_drugs + high_risk_drugs + routes AS complexity_score
  FROM 
    medication_complexity
),

-- Stratify patients into tertiles based on medication complexity score
tertiles AS (
  SELECT 
    subject_id,
    complexity_score,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM 
    complexity_score
),

-- Get hospital information
hospital_info AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    CASE 
      WHEN a.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS in_hospital_mortality,
    DATEDIFF(a.dischtime, a.admittime) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.admissions a
),

-- Get 30-day readmission information
readmission AS (
  SELECT 
    a1.subject_id,
    COUNT(DISTINCT a2.hadm_id) AS readmissions
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.admissions a1
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.admissions a2 ON a1.subject_id = a2.subject_id
  WHERE 
    a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY 
    a1.subject_id
)

-- Final calculation
SELECT 
  t.tertile,
  MIN(t.complexity_score) AS min_score,
  MAX(t.complexity_score) AS max_score,
  COUNT(DISTINCT t.subject_id) AS count,
  AVG(hi.los) AS mean_los,
  AVG(hi.in_hospital_mortality) AS in_hospital_mortality_rate,
  COALESCE(AVG(r.readmissions), 0) AS thirty_day_readmission_rate
FROM 
  tertiles t
JOIN 
  hospital_info hi ON t.subject_id = hi.subject_id
LEFT JOIN 
  readmission r ON t.subject_id = r.subject_id
WHERE 
  t.subject_id IN (
    SELECT 
      subject_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp`.patients
    WHERE 
      gender = 'F' AND anchor_age BETWEEN 78 AND 88
  )
GROUP BY 
  t.tertile
ORDER BY 
  t.tertile;