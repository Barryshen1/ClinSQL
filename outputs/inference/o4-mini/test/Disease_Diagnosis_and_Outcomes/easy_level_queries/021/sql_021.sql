WITH cohort AS (
  -- Step 1: Select female patients aged 58–68 with their admissions
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Compute length of stay in days with fractional precision
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),

dx AS (
  -- Step 2: Get diagnosis descriptions for each admission
  SELECT
    d.hadm_id,
    LOWER(diag.long_title) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
      ON d.icd_code = diag.icd_code
      AND d.icd_version = diag.icd_version
),

hadms_with_both_conditions AS (
  -- Step 3: Identify admissions having both hemorrhagic stroke and COPD exacerbation
  SELECT
    hadm_id
  FROM
    dx
  GROUP BY
    hadm_id
  HAVING
    -- At least one hemorrhagic stroke diagnosis
    SUM(CASE WHEN long_title LIKE '%hemorrhagic stroke%' THEN 1 ELSE 0 END) >= 1
    -- At least one COPD exacerbation diagnosis
    AND SUM(CASE WHEN long_title LIKE '%chronic obstructive pulmonary disease%' AND long_title LIKE '%exacerbation%' THEN 1 ELSE 0 END) >= 1
)

-- Step 4: Compute the IQR of LOS for the final cohort
SELECT
  -- 25th and 75th percentiles of LOS days
  quantiles[OFFSET(1)] AS los_25th_pct,
  quantiles[OFFSET(3)] AS los_75th_pct
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM
    cohort c
    JOIN hadms_with_both_conditions h
      ON c.hadm_id = h.hadm_id
);