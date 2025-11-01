WITH
  cohort AS (
    -- Step 1: Identify the cohort of male patients aged 45-55 with both diabetes and heart failure.
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN (
      -- Find hadm_ids with both a diabetes and a heart failure diagnosis
      SELECT
        hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      GROUP BY
        hadm_id
      HAVING
        -- Check for presence of at least one diabetes diagnosis code
        SUM(
          CASE
            WHEN (icd_code LIKE '250%' AND icd_version = 9)
              OR (icd_code LIKE 'E08%' AND icd_version = 10)
              OR (icd_code LIKE 'E09%' AND icd_version = 10)
              OR (icd_code LIKE 'E10%' AND icd_version = 10)
              OR (icd_code LIKE 'E11%' AND icd_version = 10)
              OR (icd_code LIKE 'E12%' AND icd_version = 10)
              OR (icd_code LIKE 'E13%' AND icd_version = 10)
              THEN 1
            ELSE 0
          END
        ) > 0
        AND
        -- Check for presence of at least one heart failure diagnosis code
        SUM(
          CASE
            WHEN (icd_code LIKE '428%' AND icd_version = 9) OR (icd_code LIKE 'I50%' AND icd_version = 10)
              THEN 1
            ELSE 0
          END
        ) > 0
    ) AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 45 AND 55
      AND adm.admittime IS NOT NULL
      AND adm.dischtime IS NOT NULL
  ),

  categorized_prescriptions AS (
    -- Step 2a: Categorize all prescriptions as 'Insulin' or 'Oral Antidiabetic'
    SELECT
      hadm_id,
      starttime,
      CASE
        WHEN LOWER(drug) LIKE '%insulin%'
          THEN 'Insulin'
        WHEN
          LOWER(drug) LIKE 'metformin%' OR LOWER(drug) LIKE 'glipizide%' OR LOWER(drug) LIKE 'glyburide%'
          OR LOWER(drug) LIKE 'glimepiride%' OR LOWER(drug) LIKE 'pioglitazone%' OR LOWER(drug) LIKE 'rosiglitazone%'
          OR LOWER(drug) LIKE 'sitagliptin%' OR LOWER(drug) LIKE 'saxagliptin%' OR LOWER(drug) LIKE 'linagliptin%'
          OR LOWER(drug) LIKE 'alogliptin%' OR LOWER(drug) LIKE 'canagliflozin%' OR LOWER(drug) LIKE 'dapagliflozin%'
          OR LOWER(drug) LIKE 'empagliflozin%' OR LOWER(drug) LIKE 'acarbose%' OR LOWER(drug) LIKE 'miglitol%'
          OR LOWER(drug) LIKE 'repaglinide%' OR LOWER(drug) LIKE 'nateglinide%'
          THEN 'Oral Antidiabetic'
        ELSE NULL
      END AS med_category
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      drug IS NOT NULL AND starttime IS NOT NULL
  ),

  first_initiations AS (
    -- Step 2b: Find the first initiation time for each drug class per admission
    SELECT
      hadm_id,
      med_category,
      MIN(starttime) AS initiation_time
    FROM categorized_prescriptions
    WHERE
      med_category IS NOT NULL
    GROUP BY
      hadm_id,
      med_category
  ),

  classified_initiations AS (
    -- Step 3: Classify each initiation into the 'first_12h' or 'final_72h' window
    SELECT
      c.hadm_id,
      fi.med_category,
      CASE
        -- First 12h window has priority to avoid double counting for short stays
        WHEN fi.initiation_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
          THEN 'first_12h'
        -- Final 72h window
        WHEN fi.initiation_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
          THEN 'final_72h'
        ELSE NULL
      END AS initiation_window
    FROM cohort AS c
    INNER JOIN first_initiations AS fi
      ON c.hadm_id = fi.hadm_id
  )

-- Step 4: Aggregate results and compute the final rates and difference
SELECT
  med_cats.med_category,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN ci.initiation_window = 'first_12h' THEN ci.hadm_id END),
    total_patients.n
  ) * 100 AS initiation_rate_first_12h,
  SAFE_DIVIDE(
    COUNT(DISTINCT CASE WHEN ci.initiation_window = 'final_72h' THEN ci.hadm_id END),
    total_patients.n
  ) * 100 AS initiation_rate_final_72h,
  (
    SAFE_DIVIDE(
      COUNT(DISTINCT CASE WHEN ci.initiation_window = 'first_12h' THEN ci.hadm_id END),
      total_patients.n
    ) * 100
  ) - (
    SAFE_DIVIDE(
      COUNT(DISTINCT CASE WHEN ci.initiation_window = 'final_72h' THEN ci.hadm_id END),
      total_patients.n
    ) * 100
  ) AS pp_difference
FROM
  -- Base table of medication categories to ensure both are in the output
  (SELECT 'Insulin' AS med_category UNION ALL SELECT 'Oral Antidiabetic' AS med_category) AS med_cats
LEFT JOIN classified_initiations AS ci
  ON med_cats.med_category = ci.med_category
-- Denominator for rate calculation: total number of patients in the cohort
CROSS JOIN (
  SELECT
    COUNT(DISTINCT hadm_id) AS n
  FROM cohort
) AS total_patients
GROUP BY
  med_cats.med_category,
  total_patients.n
ORDER BY
  med_cats.med_category;