WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_version = 10 
      AND (icd_code LIKE 'J1%' OR icd_code LIKE 'J18%')  -- Simplified pneumonia ICD-10 codes; fixed operator precedence
    )
),

-- Step 2: Calculate composite risk score (example; actual formula not provided)
risk_score AS (
  SELECT 
    subject_id,
    hadm_id,
    -- Example composite risk score; replace with actual formula
    (anchor_age + 
     CASE WHEN deathtime IS NOT NULL THEN 1 ELSE 0 END + 
     -- Add other risk factors here
     0) AS composite_score
  FROM cohort
),

-- Step 3: Stratify by quintiles of the composite risk score
quintiles AS (
  SELECT 
    hadm_id,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM risk_score
),

-- Step 4: Calculate outcomes
outcomes AS (
  SELECT 
    q.quintile,
    c.hadm_id,
    -- 30-day mortality
    CASE 
      WHEN c.deathtime IS NOT NULL AND DATETIME_DIFF(c.deathtime, c.admittime, DAY) <= 30 THEN 1 
      WHEN c.dod IS NOT NULL AND DATETIME_DIFF(c.dod, c.admittime, DAY) <= 30 THEN 1 
      ELSE 0 
    END AS mortality_30d,
    -- Cardiovascular complications (example; actual ICD codes may vary)
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = c.hadm_id AND d.icd_code LIKE 'I%'  -- Simplified cardiovascular ICD-10 codes
    ) AS cv_complication,
    -- Neurologic complications (example; actual ICD codes may vary)
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = c.hadm_id AND (d.icd_code LIKE 'G%' OR d.icd_code LIKE 'I6%')  -- Simplified neurologic ICD-10 codes
    ) AS neuro_complication,
    -- LOS among survivors
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM cohort c
  JOIN quintiles q ON c.hadm_id = q.hadm_id
)

-- Final aggregation
SELECT 
  quintile,
  AVG(CAST(mortality_30d AS INT64)) AS mortality_30d_rate,
  AVG(CAST(cv_complication AS INT64)) AS cv_complication_rate,
  AVG(CAST(neuro_complication AS INT64)) AS neuro_complication_rate,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los_survivors  -- Median LOS for survivors
FROM outcomes
WHERE los IS NOT NULL  -- Survivors
GROUP BY quintile
ORDER BY quintile;