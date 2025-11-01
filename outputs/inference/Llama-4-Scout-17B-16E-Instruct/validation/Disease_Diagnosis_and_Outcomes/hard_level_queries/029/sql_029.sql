WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE 
      WHEN p.gender = 'F' AND p.anchor_age BETWEEN 82 AND 92 THEN 1
      ELSE 0
    END AS include_in_analysis
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    a.hospital_expire_flag = 0 AND
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id AND d.icd_code LIKE '481%'
    )
),

-- Calculate risk score (for simplicity, assume a basic risk score for demonstration)
risk_scores AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Example risk score calculation (this needs adjustment based on actual formula)
    anchor_age * 0.1 + 
    CASE 
      WHEN hospital_expire_flag = 1 THEN 1
      ELSE 0
    END * 10 AS risk_score
  FROM 
    patients_of_interest
  WHERE 
    include_in_analysis = 1
),

-- Stratify into quintiles
quintiles AS (
  SELECT 
    subject_id,
    hadm_id,
    risk_score,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM 
    risk_scores
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    q.hadm_id,
    q.quintile,
    CASE 
      WHEN poi.deathtime IS NOT NULL OR poi.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS thirty_day_mortality,
    -- Additional outcomes (cardiovascular and neurologic complications)
    -- For simplicity, assume ICD codes for these conditions
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = q.hadm_id AND d.icd_code LIKE 'I%'  -- Cardiovascular
    ) AS cardiovascular_complication,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = q.hadm_id AND d.icd_code LIKE 'G%'  -- Neurologic
    ) AS neurologic_complication,
    DATE_DIFF(poi.dischtime, poi.admittime) AS los
  FROM 
    quintiles q
  JOIN 
    patients_of_interest poi
  ON 
    q.hadm_id = poi.hadm_id
)

-- Final aggregation
SELECT 
  quintile,
  AVG(thirty_day_mortality) AS thirty_day_mortality_rate,
  AVG(cardiovascular_complication) AS cardiovascular_complication_rate,
  AVG(neurologic_complication) AS neurologic_complication_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) OVER (PARTITION BY quintile) AS median_los
FROM 
  outcomes
GROUP BY 
  quintile;