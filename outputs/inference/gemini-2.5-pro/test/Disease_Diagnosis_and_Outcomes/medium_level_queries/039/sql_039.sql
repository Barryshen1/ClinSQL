WITH
-- Step 1: Identify all hospital admissions for female patients aged 66-76
cohort_base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    -- Standard age calculation for MIMIC-IV
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 66 AND 76
),

-- Step 2: Find all hospital admissions with a diagnosis of AMI
ami_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for AMI start with 410
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '410')
    -- ICD-10 codes for AMI start with I21 or I22
    OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('I21', 'I22'))
),

-- Step 3: Find admissions with an initial diagnosis of shock or respiratory failure to exclude them
exclusion_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  -- 'Initial' is proxied by a diagnosis sequence number of 1 or 2
  WHERE seq_num <= 2 AND
  (
    -- ICD-9 codes (no dots) for shock and respiratory failure
    (icd_version = 9 AND (
      SUBSTR(icd_code, 1, 4) = '7855' -- Shock
      OR icd_code IN ('51881', '51882', '51884') -- Acute respiratory failure
    )) OR
    -- ICD-10 codes (no dots) for shock and respiratory failure
    (icd_version = 10 AND (
      SUBSTR(icd_code, 1, 3) = 'R57' -- Shock
      OR icd_code = 'R6521' -- Severe sepsis with septic shock
      OR SUBSTR(icd_code, 1, 4) IN ('J960', 'J962') -- Acute respiratory failure
    ))
  )
),

-- Step 4: Build the final cohort by applying filters and calculating derived fields
final_cohort AS (
  SELECT
    cb.hadm_id,
    cb.hospital_expire_flag,
    -- Categorize admission type into 'Emergent' vs 'Non-Emergent'
    CASE
      WHEN cb.admission_type IN ('EMERGENCY', 'URGENT', 'EW EMER', 'DIRECT EMER')
        THEN 'Emergent'
      ELSE 'Non-Emergent'
    END AS admission_category,
    -- Calculate LOS in days and create categories
    CASE
      WHEN CEIL(DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0) BETWEEN 1 AND 3 THEN '1-3'
      WHEN CEIL(DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0) BETWEEN 4 AND 7 THEN '4-7'
      WHEN CEIL(DATETIME_DIFF(cb.dischtime, cb.admittime, HOUR) / 24.0) >= 8 THEN '>=8'
      ELSE NULL
    END AS los_category,
    -- Calculate time to death in days for patients who died in hospital
    CASE
      WHEN cb.hospital_expire_flag = 1 THEN DATETIME_DIFF(cb.deathtime, cb.admittime, DAY)
      ELSE NULL
    END AS time_to_death_days
  FROM cohort_base AS cb
  -- Keep only admissions with an AMI diagnosis
  INNER JOIN ami_hadms AS ah
    ON cb.hadm_id = ah.hadm_id
  -- Exclude admissions with initial shock or respiratory failure
  LEFT JOIN exclusion_hadms AS eh
    ON cb.hadm_id = eh.hadm_id
  WHERE
    eh.hadm_id IS NULL
)

-- Step 5: Aggregate results and calculate final metrics, stratified by LOS and admission type
SELECT
  los_category,
  admission_category,
  COUNT(hadm_id) AS number_of_patients,
  SUM(hospital_expire_flag) AS number_of_deaths,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_percent,
  -- Calculate median using APPROX_QUANTILES, which ignores NULLs
  APPROX_QUANTILES(time_to_death_days, 2)[OFFSET(1)] AS median_time_to_death_days
FROM
  final_cohort
WHERE
  los_category IS NOT NULL -- Exclude stays that don't fit into the LOS categories (e.g., < 1 day)
GROUP BY
  los_category,
  admission_category
ORDER BY
  -- Custom sort to ensure logical ordering of LOS categories
  CASE los_category
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    WHEN '>=8' THEN 3
  END,
  admission_category;