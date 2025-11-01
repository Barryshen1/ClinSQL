WITH 
-- Filter and calculate composite risk score (for simplicity, assume it's directly available or calculated)
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    d.icd_code,
    d.long_title AS diagnosis
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND d.long_title LIKE '%Intracranial hemorrhage%'
),

-- Calculate outcomes
admission_outcomes AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    anchor_age,
    -- Assume a simple definition for now; adjust based on actual requirements
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1 
      ELSE 0 
    END AS thirty_day_mortality,
    -- For simplicity, assume major complication is indicated by certain ICD codes or DRG codes
    CASE 
      WHEN diagnosis LIKE '%complication%' THEN 1 
      ELSE 0 
    END AS major_complication,
    DATE_DIFF(dischtime, admittime) AS los
  FROM 
    filtered_admissions
),

-- Stratify into quintiles based on age (modify to risk score if available)
quintiles AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    anchor_age,
    thirty_day_mortality,
    major_complication,
    los,
    NTILE(5) OVER (ORDER BY anchor_age) AS age_quintile
  FROM 
    admission_outcomes
)

-- Calculate statistics per quintile
SELECT 
  age_quintile,
  COUNT(*) AS n,
  AVG(thirty_day_mortality) * 100 AS thirty_day_mortality_percent,
  AVG(major_complication) * 100 AS major_complication_percent,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) OVER () AS median_survivor_los
FROM 
  quintiles
WHERE 
  thirty_day_mortality = 0  -- Consider only survivors for LOS
GROUP BY 
  age_quintile
ORDER BY 
  age_quintile;