WITH 
-- Identify cardiac arrest patients, female, aged 59-69
cardiac_arrest_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.gender, 
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
      AND d.icd_code LIKE '%427.5%'  -- Cardiac arrest
    )
),

-- Assume a simple risk score for demonstration
risk_score AS (
  SELECT 
    subject_id, 
    hadm_id,
    -- Simplified example: risk score based on age
    CASE 
      WHEN anchor_age = 59 THEN 1
      WHEN anchor_age = 60 THEN 2
      ELSE 3
    END AS risk_score
  FROM 
    cardiac_arrest_patients
),

-- Stratify into quartiles
quartiles AS (
  SELECT 
    subject_id, 
    hadm_id,
    risk_score,
    NTILE(4) OVER (ORDER BY risk_score) AS quartile
  FROM 
    risk_score
),

-- Calculate 30-day mortality, complications, and LOS for each quartile
outcomes AS (
  SELECT 
    q.quartile,
    COUNT(DISTINCT CASE WHEN a.deathtime IS NOT NULL AND DATE_DIFF(a.deathtime, a.admittime) <= 30 THEN a.hadm_id END) / COUNT(DISTINCT a.hadm_id) AS thirty_day_mortality_rate,
    -- Cardiovascular and neurologic complications: placeholder, actual implementation requires ICD code analysis
    0 AS cardiovascular_complication_rate,  -- Requires ICD code analysis
    0 AS neurologic_complication_rate,      -- Requires ICD code analysis
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DATE_DIFF(a.dischtime, a.admittime)) AS median_survivor_los
  FROM 
    quartiles q
  JOIN 
    cardiac_arrest_patients a ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  WHERE 
    a.deathtime IS NULL OR DATE_DIFF(a.deathtime, a.admittime) > 30
  GROUP BY 
    q.quartile
),

-- Baseline 30-day mortality for all female patients aged 59-69
baseline_mortality AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN a.deathtime IS NOT NULL AND DATE_DIFF(a.deathtime, a.admittime) <= 30 THEN a.hadm_id END) / COUNT(DISTINCT a.hadm_id) AS baseline_thirty_day_mortality_rate
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
)

-- Final query
SELECT 
  o.quartile,
  o.thirty_day_mortality_rate,
  o.cardiovascular_complication_rate,
  o.neurologic_complication_rate,
  o.median_survivor_los,
  bm.baseline_thirty_day_mortality_rate
FROM 
  outcomes o
CROSS JOIN 
  baseline_mortality bm;