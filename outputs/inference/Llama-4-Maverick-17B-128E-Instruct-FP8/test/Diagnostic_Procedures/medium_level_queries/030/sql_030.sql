WITH 
-- Step 1 & 2: Filter patients and identify relevant admissions
relevant_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN (
        -- Example ICD codes for upper GI bleeding; actual codes may vary
        'K92.2', '578.9', '578.0', '578.1'
      )
    )
),

-- Step 3: Calculate length of stay and filter
admissions_with_los AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM 
    relevant_admissions
  WHERE 
    DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 8
),

-- Step 4: Count diagnostic procedures per admission
procedure_counts AS (
  SELECT 
    a.hadm_id,
    COUNT(p.icd_code) AS num_procedures,
    CASE 
      WHEN a.los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.los BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_group
  FROM 
    admissions_with_los a
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  GROUP BY 
    a.hadm_id, a.los
),

-- Step 5: Calculate percentiles
percentiles AS (
  SELECT 
    los_group,
    APPROX_QUANTILES(num_procedures, 100) AS quantiles
  FROM 
    procedure_counts
  GROUP BY 
    los_group
)

SELECT 
  los_group,
  quantiles[OFFSET(25)] AS p25,
  quantiles[OFFSET(50)] AS p50,
  quantiles[OFFSET(75)] AS p75
FROM 
  percentiles;