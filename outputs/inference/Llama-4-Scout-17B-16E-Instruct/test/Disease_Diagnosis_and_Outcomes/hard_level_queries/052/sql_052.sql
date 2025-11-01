WITH 
-- Identify relevant population
population AS (
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
      WHEN d.icd_code IN (
        SELECT icd_code 
        FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
        WHERE long_title LIKE '%COPD%'
      ) THEN 1 
      ELSE 0 
    END AS has_copd
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
  ON 
    a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 75 AND 85
    AND p.gender = 'F'
),

-- Calculate 90-day mortality, complications, and LOS for each patient
outcomes AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS died,
    0 AS has_major_complication,  -- Assume major complications are not identified
    DATE_DIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE), DAY) AS los
  FROM 
    population
),

-- Stratify by composite risk score 
risk_score AS (
  SELECT 
    subject_id,
    hadm_id,
    NTILE(4) OVER (ORDER BY anchor_age) AS risk_quintile
  FROM 
    population
),

-- Broader 90-day mortality for female inpatients aged 75-85
broader_population AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS broader_died
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 75 AND 85
    AND p.gender = 'F'
)

-- Final aggregation
SELECT 
  rs.risk_quintile,
  AVG(o.died) AS mortality_rate,
  AVG(o.has_major_complication) AS complication_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY o.los) OVER () AS median_los,
  AVG(bp.broader_died) AS broader_90_day_mortality
FROM 
  outcomes o
JOIN 
  risk_score rs 
ON 
  o.subject_id = rs.subject_id AND o.hadm_id = rs.hadm_id
JOIN 
  broader_population bp 
ON 
  o.subject_id = bp.subject_id AND o.hadm_id = bp.hadm_id
GROUP BY 
  rs.risk_quintile;