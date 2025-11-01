WITH
-- Step 1: Create a base cohort of male patients aged 53-63 with a hospital admission.
patient_base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 53 AND 63
),

-- Step 2a: Pre-aggregate diagnosis flags for each hospital admission.
diagnosis_flags AS (
  SELECT
    hadm_id,
    -- Flag for at least one Diabetes diagnosis code
    COUNT(
      CASE
        WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250')
             OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
        THEN icd_code
      END
    ) > 0 AS has_diabetes,
    -- Flag for at least one Heart Failure diagnosis code
    COUNT(
      CASE
        WHEN (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428')
             OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
        THEN icd_code
      END
    ) > 0 AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),

-- Step 2b: Filter the base cohort for patients diagnosed with both diabetes and heart failure.
diagnosed_cohort AS (
  SELECT
    pb.hadm_id,
    pb.admittime,
    pb.dischtime
  FROM
    patient_base AS pb
  INNER JOIN
    diagnosis_flags AS df
    ON pb.hadm_id = df.hadm_id
  WHERE
    df.has_diabetes AND df.has_hf
),

-- Step 3: Identify the first initiation time of an injectable GLP-1 RA for each hospital admission.
glp1ra_initiations AS (
  SELECT
    hadm_id,
    MIN(starttime) AS first_starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- A list of common generic and brand names for GLP-1 RAs
    (
      LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%lixisenatide%'
      OR LOWER(drug) LIKE '%byetta%'
      OR LOWER(drug) LIKE '%bydureon%'
      OR LOWER(drug) LIKE '%victoza%'
      OR LOWER(drug) LIKE '%trulicity%'
      OR LOWER(drug) LIKE '%ozempic%'
    )
    -- Filter for injectable routes by excluding common oral/enteral routes
    AND route NOT IN ('PO', 'PO/NG', 'NG', 'GT', 'OG', 'JT')
    AND starttime IS NOT NULL
  GROUP BY
    hadm_id
)

-- Step 4: Join the final cohort with medication data and calculate the final percentages.
SELECT
  -- Percentage initiated within the first 24 hours of admission
  100.0 * COUNTIF(
    g.first_starttime IS NOT NULL
    AND g.first_starttime <= DATETIME_ADD(dc.admittime, INTERVAL 24 HOUR)
  ) / COUNT(dc.hadm_id) AS percentage_initiated_first_24h,

  -- Percentage initiated within the final 12 hours before discharge
  100.0 * COUNTIF(
    g.first_starttime IS NOT NULL
    AND g.first_starttime >= DATETIME_SUB(dc.dischtime, INTERVAL 12 HOUR)
    AND g.first_starttime <= dc.dischtime
  ) / COUNT(dc.hadm_id) AS percentage_initiated_last_12h
FROM
  diagnosed_cohort AS dc
LEFT JOIN
  glp1ra_initiations AS g
  ON dc.hadm_id = g.hadm_id;