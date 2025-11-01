WITH 
-- Identify patients with acute myocardial infarction (AMI) and relevant demographics
patients_ami AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN (
          '410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9'
        )
    )
),

-- Calculate major complications (for simplicity, assume specific ICD codes indicate major complications)
major_complications AS (
  SELECT 
    subject_id,
    hadm_id,
    COUNT(DISTINCT icd_code) AS num_complications
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN (
      -- Example ICD codes for major complications
      '997.1', '998.2', '999.0'
    )
  GROUP BY 
    subject_id, hadm_id
),

-- Calculate composite risk score (age + number of major complications)
risk_scores AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.anchor_age AS age,
    COALESCE(m.num_complications, 0) AS num_complications,
    p.anchor_age + COALESCE(m.num_complications, 0) AS composite_risk_score
  FROM 
    patients_ami p
  LEFT JOIN 
    major_complications m 
      ON p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
),

-- Stratify patients into quintiles based on composite risk score
quintiles AS (
  SELECT 
    subject_id,
    hadm_id,
    composite_risk_score,
    NTILE(5) OVER (ORDER BY composite_risk_score) AS quintile
  FROM 
    risk_scores
),

-- Calculate outcomes for each quintile
outcomes AS (
  SELECT 
    q.quintile,
    AVG(CASE WHEN q.subject_id IN (SELECT subject_id FROM patients_ami WHERE hospital_expire_flag = 1) THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(CASE WHEN m.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS complication_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY TIMESTAMPDIFF(DAY, a.admittime, COALESCE(a.dischtime, a.deathtime))) AS median_los
  FROM 
    quintiles q
  JOIN 
    patients_ami a 
      ON q.subject_id = a.subject_id AND q.hadm_id = a.hadm_id
  LEFT JOIN 
    major_complications m 
      ON q.subject_id = m.subject_id AND q.hadm_id = m.hadm_id
  GROUP BY 
    q.quintile
)

SELECT 
  quintile,
  mortality_rate * 100 AS mortality_rate_percent,
  complication_rate * 100 AS complication_rate_percent,
  median_los
FROM 
  outcomes
ORDER BY 
  quintile;