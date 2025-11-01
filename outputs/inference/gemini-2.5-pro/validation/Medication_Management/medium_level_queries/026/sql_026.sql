WITH
-- Step 1: Identify the cohort of hospital admissions for females aged 38-48 with T2D and Heart Failure.
cohort_hadm AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.anchor_age BETWEEN 38 AND 48
  GROUP BY
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    -- Ensure at least one T2D and one HF diagnosis for the admission
    COUNT(DISTINCT
      CASE
        WHEN (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%' AND SUBSTR(d.icd_code, 5, 1) NOT IN ('1', '3')) THEN 'T2D'
        WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%') THEN 'HF'
      END
    ) = 2
),

-- Step 2: Classify relevant medication prescriptions for the cohort
medications AS (
  SELECT
    hadm_id,
    starttime,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN
           LOWER(drug) LIKE '%metformin%'
        OR LOWER(drug) LIKE '%glipizide%'
        OR LOWER(drug) LIKE '%glyburide%'
        OR LOWER(drug) LIKE '%glimepiride%'
        OR LOWER(drug) LIKE '%pioglitazone%'
        OR LOWER(drug) LIKE '%rosiglitazone%'
        OR LOWER(drug) LIKE '%sitagliptin%'
        OR LOWER(drug) LIKE '%saxagliptin%'
        OR LOWER(drug) LIKE '%linagliptin%'
        OR LOWER(drug) LIKE '%alogliptin%'
        OR LOWER(drug) LIKE '%canagliflozin%'
        OR LOWER(drug) LIKE '%dapagliflozin%'
        OR LOWER(drug) LIKE '%empagliflozin%'
        OR LOWER(drug) LIKE '%repaglinide%'
        OR LOWER(drug) LIKE '%nateglinide%'
        OR LOWER(drug) LIKE '%acarbose%'
        THEN 'Oral Agent'
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    -- Pre-filter for performance
    hadm_id IN (SELECT hadm_id FROM cohort_hadm)
    AND starttime IS NOT NULL
),

-- Step 3: Find the first administration time for each drug class per admission
first_meds AS (
  SELECT
    m.hadm_id,
    m.drug_class,
    MIN(m.starttime) AS first_starttime
  FROM medications AS m
  WHERE m.drug_class IS NOT NULL
  GROUP BY
    m.hadm_id,
    m.drug_class
),

-- Step 4: Flag admissions based on when medications were initiated (first 72h vs. final 72h)
initiation_flags AS (
  SELECT
    c.hadm_id,
    -- Flags for the first 72 hours
    MAX(
      CASE
        WHEN fm.drug_class = 'Insulin'
          AND fm.first_starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0
      END
    ) AS insulin_first_72h,
    MAX(
      CASE
        WHEN fm.drug_class = 'Oral Agent'
          AND fm.first_starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0
      END
    ) AS oral_agent_first_72h,
    -- Flags for the final 72 hours
    MAX(
      CASE
        WHEN fm.drug_class = 'Insulin'
          AND fm.first_starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
          -- Exclude if initiation already counted in the first 72h window
          AND fm.first_starttime > DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0
      END
    ) AS insulin_final_72h,
    MAX(
      CASE
        WHEN fm.drug_class = 'Oral Agent'
          AND fm.first_starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
          -- Exclude if initiation already counted in the first 72h window
          AND fm.first_starttime > DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0
      END
    ) AS oral_agent_final_72h
  FROM
    cohort_hadm AS c
  LEFT JOIN
    first_meds AS fm
    ON c.hadm_id = fm.hadm_id
  GROUP BY
    c.hadm_id
)

-- Step 5: Calculate and present the final percentages
SELECT
  'First 72h' AS time_window,
  SAFE_DIVIDE(SUM(flags.insulin_first_72h), COUNT(c.hadm_id)) * 100 AS percentage_initiated_on_insulin,
  SAFE_DIVIDE(SUM(flags.oral_agent_first_72h), COUNT(c.hadm_id)) * 100 AS percentage_initiated_on_oral_agent
FROM
  cohort_hadm AS c
LEFT JOIN
  initiation_flags AS flags ON c.hadm_id = flags.hadm_id

UNION ALL

SELECT
  'Final 72h' AS time_window,
  SAFE_DIVIDE(SUM(flags.insulin_final_72h), COUNT(c.hadm_id)) * 100 AS percentage_initiated_on_insulin,
  SAFE_DIVIDE(SUM(flags.oral_agent_final_72h), COUNT(c.hadm_id)) * 100 AS percentage_initiated_on_oral_agent
FROM
  cohort_hadm AS c
LEFT JOIN
  initiation_flags AS flags ON c.hadm_id = flags.hadm_id;