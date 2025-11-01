WITH
Cohort AS (
  -- Step 1: Identify the cohort of hospital admissions for patients aged 48-58 with both T2DM and HF.
  SELECT
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    -- Filter by age at admission
    (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 48 AND 58
    -- Ensure both diagnoses are present for the admission
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
      WHERE LOWER(long_title) LIKE '%type 2 diabetes%' OR LOWER(long_title) LIKE '%type ii diabetes%'
    )
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
      WHERE LOWER(long_title) LIKE '%heart failure%'
    )
    -- We need dischtime to calculate the last 48h window
    AND adm.dischtime IS NOT NULL
),

GLP1_Prescriptions AS (
  -- Step 2: Identify all prescriptions for injectable GLP-1 agonists
  SELECT
    hadm_id,
    starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- Filter for common injectable routes, excluding oral
    route IN ('SC', 'IM')
    -- Filter for GLP-1 agonist drug names
    AND (
      LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%lixisenatide%'
    )
)

-- Step 3: Join cohort with prescriptions and calculate initiation rates and the difference
SELECT
  -- Calculate the rate of initiation in the first 72 hours
  SAFE_DIVIDE(
    COUNT(DISTINCT
      CASE
        WHEN DATETIME_DIFF(p.starttime, c.admittime, HOUR) BETWEEN 0 AND 72
        THEN c.hadm_id
      END),
    COUNT(DISTINCT c.hadm_id)
  ) * 100 AS initiation_rate_first_72h_pct,

  -- Calculate the rate of initiation in the last 48 hours
  SAFE_DIVIDE(
    COUNT(DISTINCT
      CASE
        WHEN DATETIME_DIFF(c.dischtime, p.starttime, HOUR) BETWEEN 0 AND 48
        THEN c.hadm_id
      END),
    COUNT(DISTINCT c.hadm_id)
  ) * 100 AS initiation_rate_last_48h_pct,

  -- Calculate the absolute difference in percentage points
  ABS(
    (
      SAFE_DIVIDE(
        COUNT(DISTINCT
          CASE
            WHEN DATETIME_DIFF(p.starttime, c.admittime, HOUR) BETWEEN 0 AND 72
            THEN c.hadm_id
          END),
        COUNT(DISTINCT c.hadm_id)
      ) * 100
    ) - (
      SAFE_DIVIDE(
        COUNT(DISTINCT
          CASE
            WHEN DATETIME_DIFF(c.dischtime, p.starttime, HOUR) BETWEEN 0 AND 48
            THEN c.hadm_id
          END),
        COUNT(DISTINCT c.hadm_id)
      ) * 100
    )
  ) AS absolute_difference_pp

FROM Cohort AS c
LEFT JOIN GLP1_Prescriptions AS p
  ON c.hadm_id = p.hadm_id;