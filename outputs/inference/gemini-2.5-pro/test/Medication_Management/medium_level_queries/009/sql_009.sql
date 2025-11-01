WITH
  cohort AS (
    -- Step 1: Define the cohort of male patients aged 68-78 with diabetes and acute HF
    SELECT
      p.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
    WHERE
      p.gender = 'M'
      AND (
        DATETIME_DIFF(
          adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR
        ) + p.anchor_age
      ) BETWEEN 68 AND 78
      -- Ensure the first and final 24h periods are distinct
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 48
      -- Filter for patients with a diagnosis of Diabetes
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND (
            dx.icd_code LIKE '250%' -- Diabetes Mellitus, ICD-9
            OR dx.icd_code LIKE 'E08%' -- Diabetes due to underlying condition
            OR dx.icd_code LIKE 'E09%' -- Drug or chemical induced diabetes
            OR dx.icd_code LIKE 'E10%' -- Type 1 diabetes
            OR dx.icd_code LIKE 'E11%' -- Type 2 diabetes
            OR dx.icd_code LIKE 'E13%' -- Other specified diabetes
          )
      )
      -- Filter for patients with a diagnosis of Acute Heart Failure
      AND EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
        WHERE
          dx.hadm_id = adm.hadm_id
          AND dx.icd_code IN (
            '428.21', -- Acute systolic heart failure (ICD-9)
            '428.31', -- Acute diastolic heart failure (ICD-9)
            '428.41', -- Acute combined systolic and diastolic heart failure (ICD-9)
            'I50.21', -- Acute systolic (congestive) heart failure (ICD-10)
            'I50.31', -- Acute diastolic (congestive) heart failure (ICD-10)
            'I50.41' -- Acute combined systolic and diastolic (congestive) heart failure (ICD-10)
          )
      )
  ),

  drug_administrations AS (
    -- Step 2: Identify insulin and oral agent prescriptions for the cohort
    SELECT
      pres.hadm_id,
      pres.starttime,
      CASE
        WHEN LOWER(pres.drug) LIKE '%insulin%'
          THEN 'Insulin'
        WHEN
          (
            LOWER(pres.drug) LIKE '%metformin%'
            OR LOWER(pres.drug) LIKE '%glipizide%'
            OR LOWER(pres.drug) LIKE '%glyburide%'
            OR LOWER(pres.drug) LIKE '%glimepiride%'
            OR LOWER(pres.drug) LIKE '%pioglitazone%'
            OR LOWER(pres.drug) LIKE '%rosiglitazone%' -- Corrected typo from `presg` to `pres`
            OR LOWER(pres.drug) LIKE '%sitagliptin%'
            OR LOWER(pres.drug) LIKE '%saxagliptin%'
            OR LOWER(pres.drug) LIKE '%linagliptin%'
            OR LOWER(pres.drug) LIKE '%alogliptin%'
            OR LOWER(pres.drug) LIKE '%canagliflozin%'
            OR LOWER(pres.drug) LIKE '%dapagliflozin%'
            OR LOWER(pres.drug) LIKE '%empagliflozin%'
            OR LOWER(pres.drug) LIKE '%repaglinide%'
            OR LOWER(pres.drug) LIKE '%nateglinide%'
            OR LOWER(pres.drug) LIKE '%acarbose%'
          )
          -- Ensure the route is oral
          AND pres.route IN ('PO', 'PO/NG', 'PO/OG', 'PO/GT')
          THEN 'Oral Agent'
        ELSE NULL
      END AS drug_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pres
    -- Refinement: Replaced `IN (SELECT ...)` subquery with a more performant INNER JOIN
    INNER JOIN
      cohort
      ON pres.hadm_id = cohort.hadm_id
  ),

  patient_flags AS (
    -- Step 3: Flag if a patient received drugs in the first/final 24h windows
    SELECT
      c.hadm_id,
      MAX(
        CASE
          WHEN
            da.drug_category = 'Insulin' AND da.starttime
            BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS insulin_first_24h,
      MAX(
        CASE
          WHEN
            da.drug_category = 'Oral Agent' AND da.starttime
            BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS oral_first_24h,
      MAX(
        CASE
          WHEN
            da.drug_category = 'Insulin' AND da.starttime
            BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            THEN 1
          ELSE 0
        END
      ) AS insulin_final_24h,
      MAX(
        CASE
          WHEN
            da.drug_category = 'Oral Agent' AND da.starttime
            BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            THEN 1
          ELSE 0
        END
      ) AS oral_final_24h
    FROM
      cohort AS c
    LEFT JOIN
      drug_administrations AS da
      ON c.hadm_id = da.hadm_id
    GROUP BY
      c.hadm_id
  )

-- Step 4: Calculate and format the final results
SELECT
  'Insulin' AS drug_type,
  100.0 * AVG(insulin_first_24h) AS rate_first_24h_pct,
  100.0 * AVG(insulin_final_24h) AS rate_final_24h_pct,
  (100.0 * AVG(insulin_final_24h)) - (100.0 * AVG(insulin_first_24h))
    AS abs_percentage_point_diff
FROM
  patient_flags
UNION ALL
SELECT
  'Oral Agent' AS drug_type,
  100.0 * AVG(oral_first_24h) AS rate_first_24h_pct,
  100.0 * AVG(oral_final_24h) AS rate_final_24h_pct,
  (100.0 * AVG(oral_final_24h)) - (100.0 * AVG(oral_first_24h))
    AS abs_percentage_point_diff
FROM
  patient_flags;