WITH 
-- Define lower GI bleeding and age range
lower_gi_bleeding_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.discharge_location IN ('42', '43', '44', '45')  -- Assuming specific discharge locations for lower GI bleeding
),

-- Assume a simple risk score based on ICD codes for complications
complication_risk_score AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS risk_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '456%'  -- Example complication codes
  GROUP BY 
    subject_id, hadm_id
),

-- Stratify patients into quintiles based on risk score
quintiles AS (
  SELECT 
    subject_id,
    hadm_id,
    risk_score,
    NTILE(5) OVER (ORDER BY risk_score) AS quintile
  FROM 
    complication_risk_score
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    q.quintile,
    COUNT(DISTINCT q.hadm_id) AS N,
    SUM(CASE WHEN a.deathtime IS NOT NULL AND a.deathtime <= TIMESTAMP_ADD(a.admittime, INTERVAL 90 DAY) THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS ninety_day_mortality_rate,
    SUM(CASE WHEN drg.drg_severity > 2 THEN 1 ELSE 0 END) / COUNT(DISTINCT q.hadm_id) AS major_complication_rate,
    APPROX_QUANTILES(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY), 5) AS median_los
  FROM 
    quintiles q
  JOIN 
    lower_gi_bleeding_patients a
  ON 
    q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` drg
  ON 
    q.hadm_id = drg.hadm_id
  WHERE 
    a.hospital_expire_flag = 0 OR a.deathtime IS NULL OR a.deathtime > TIMESTAMP_ADD(a.admittime, INTERVAL 90 DAY)
  GROUP BY 
    q.quintile
)

SELECT 
  quintile,
  N,
  ninety_day_mortality_rate,
  major_complication_rate,
  ARRAY_LENGTH(median_los) > 0 ? median_los[OFFSET(2)] : 0 AS median_los
FROM 
  outcomes
ORDER BY 
  quintile;