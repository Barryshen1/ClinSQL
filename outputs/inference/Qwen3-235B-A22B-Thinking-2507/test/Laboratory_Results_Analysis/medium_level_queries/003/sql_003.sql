WITH 
-- Step 1: Calculate age at admission for all patients
admissions_with_age AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

-- Step 2: Filter for female patients aged 36-46
filtered_admissions AS (
  SELECT *
  FROM admissions_with_age
  WHERE gender = 'F'
    AND age_at_admission BETWEEN 36 AND 46
),

-- Step 3: Get admissions with primary ischemic heart disease diagnosis (I20-I25)
ischemic_admissions AS (
  SELECT 
    f.hadm_id,
    f.admittime,
    f.dischtime
  FROM filtered_admissions f
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  WHERE d.seq_num = 1  -- Primary diagnosis
    AND (
      d.icd_code LIKE 'I20%' OR
      d.icd_code LIKE 'I21%' OR
      d.icd_code LIKE 'I22%' OR
      d.icd_code LIKE 'I23%' OR
      d.icd_code LIKE 'I24%' OR
      d.icd_code LIKE 'I25%'
    )
),

-- Step 4: Get first Troponin T (hs) measurement per admission
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN ischemic_admissions i
    ON l.hadm_id = i.hadm_id
  WHERE l.itemid = 50341  -- High-sensitivity Troponin T
    AND l.charttime >= i.admittime
    AND l.charttime <= i.dischtime
    AND l.valuenum IS NOT NULL  -- Exclude non-numeric values
),

-- Step 5: Filter for initial Troponin > ULN
qualifying_admissions AS (
  SELECT 
    troponin_value
  FROM first_troponin
  WHERE rn = 1  -- First measurement
    AND troponin_value > (
      SELECT ref_range_upper 
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
      WHERE itemid = 50341
    )
)

-- Step 6: Calculate statistics on qualifying Troponin values
SELECT 
  MIN(troponin_value) OVER () AS min_value,
  MAX(troponin_value) OVER () AS max_value,
  PERCENTILE_CONT(troponin_value, 0.25) OVER () AS p25,
  PERCENTILE_CONT(troponin_value, 0.50) OVER () AS p50,
  PERCENTILE_CONT(troponin_value, 0.75) OVER () AS p75
FROM qualifying_admissions
LIMIT 1;