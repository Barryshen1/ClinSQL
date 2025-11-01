WITH
  -- Step 1: Identify the cohort of female patients aged 67-77 with T2DM and HF.
  cohort_hadm AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      -- Calculate age at admission and filter
      AND (
        TIMESTAMP_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR) + pat.anchor_age
      ) BETWEEN 67 AND 77
      AND adm.hadm_id IS NOT NULL
      -- Filter for admissions with a T2DM diagnosis
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          hadm_id = adm.hadm_id
          AND (
            icd_code LIKE 'E11%' -- ICD-10 for T2DM
            OR icd_code LIKE '250%' -- ICD-9 for Diabetes
          )
      )
      -- Filter for admissions with a Heart Failure diagnosis
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          hadm_id = adm.hadm_id
          AND (
            icd_code LIKE 'I50%' -- ICD-10 for Heart Failure
            OR icd_code LIKE '428%' -- ICD-9 for Heart Failure
          )
      )
  ),
  -- Step 2: Get the total number of patients in the cohort for percentage calculation.
  cohort_stats AS (
    SELECT COUNT(DISTINCT hadm_id) AS total_patients
    FROM cohort_hadm
  ),
  -- Step 3: Classify prescriptions into the specified drug classes for the cohort.
  classified_prescriptions AS (
    SELECT
      hadm_id,
      starttime,
      CASE
        WHEN LOWER(drug) LIKE '%metformin%'
        THEN 'Metformin'
        WHEN
          LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%'
        THEN 'Sulfonylurea (SU)'
        WHEN
          LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%januvia%' OR LOWER(drug) LIKE '%saxagliptin%'
          OR LOWER(drug) LIKE '%onglyza%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%tradjenta%'
          OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%nesina%'
        THEN 'DPP-4 Inhibitor'
        WHEN
          LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%invokana%' OR LOWER(drug) LIKE '%dapagliflozin%'
          OR LOWER(drug) LIKE '%farxiga%' OR LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%jardiance%'
          OR LOWER(drug) LIKE '%ertugliflozin%' OR LOWER(drug) LIKE '%steglatro%'
        THEN 'SGLT2 Inhibitor'
        WHEN
          LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%byetta%' OR LOWER(drug) LIKE '%bydureon%'
          OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%victoza%' OR LOWER(drug) LIKE '%semaglutide%'
          OR LOWER(drug) LIKE '%ozempic%' OR LOWER(drug) LIKE '%rybelsus%' OR LOWER(drug) LIKE '%dulaglutide%'
          OR LOWER(drug) LIKE '%trulicity%' OR LOWER(drug) LIKE '%lixisenatide%' OR LOWER(drug) LIKE '%adlyxin%'
        THEN 'GLP-1 Agonist'
        WHEN
          LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%actos%' OR LOWER(drug) LIKE '%rosiglitazone%'
          OR LOWER(drug) LIKE '%avandia%'
        THEN 'TZD'
        WHEN
          LOWER(drug) LIKE '%insulin%' OR LOWER(drug) LIKE '%humalog%' OR LOWER(drug) LIKE '%novolog%'
          OR LOWER(drug) LIKE '%lantus%' OR LOWER(drug) LIKE '%levemir%' OR LOWER(drug) LIKE '%apidra%'
          OR LOWER(drug) LIKE '%humulin%' OR LOWER(drug) LIKE '%novolin%'
        THEN 'Insulin'
        ELSE NULL
      END AS drug_class
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE hadm_id IN (SELECT hadm_id FROM cohort_hadm)
  ),
  -- Step 4: For each patient and drug class, flag if initiated in the first 12h or final 48h.
  initiations_by_hadm AS (
    SELECT
      ch.hadm_id,
      cp.drug_class,
      MAX(
        CASE
          WHEN
            cp.starttime >= ch.admittime AND cp.starttime <= TIMESTAMP_ADD(ch.admittime, INTERVAL 12 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS initiated_first_12h,
      MAX(
        CASE
          WHEN
            cp.starttime >= TIMESTAMP_SUB(ch.dischtime, INTERVAL 48 HOUR) AND cp.starttime <= ch.dischtime
            THEN 1
          ELSE 0
        END
      ) AS initiated_final_48h
    FROM cohort_hadm AS ch
    JOIN classified_prescriptions AS cp
      ON ch.hadm_id = cp.hadm_id
    WHERE cp.drug_class IS NOT NULL
    GROUP BY
      ch.hadm_id,
      cp.drug_class
  ),
  -- Step 5: Aggregate initiation counts for each drug class across the cohort.
  class_level_summary AS (
    SELECT
      drug_class,
      COUNT(DISTINCT CASE WHEN initiated_first_12h = 1 THEN hadm_id END) AS count_first_12h,
      COUNT(DISTINCT CASE WHEN initiated_final_48h = 1 THEN hadm_id END) AS count_final_48h
    FROM initiations_by_hadm
    GROUP BY
      drug_class
  ),
  -- Step 6: Create a list of all drug classes to ensure they all appear in the final report.
  all_drug_classes AS (
    SELECT 'Insulin' AS drug_class UNION ALL
    SELECT 'Metformin' UNION ALL
    SELECT 'Sulfonylurea (SU)' UNION ALL
    SELECT 'DPP-4 Inhibitor' UNION ALL
    SELECT 'SGLT2 Inhibitor' UNION ALL
    SELECT 'GLP-1 Agonist' UNION ALL
    SELECT 'TZD'
  )
-- Final Step: Combine results, calculate percentages and the net change.
SELECT
  adc.drug_class,
  SAFE_DIVIDE(COALESCE(cls.count_first_12h, 0) * 100.0, cs.total_patients) AS initiation_pct_first_12h,
  SAFE_DIVIDE(COALESCE(cls.count_final_48h, 0) * 100.0, cs.total_patients) AS initiation_pct_final_48h,
  (
    SAFE_DIVIDE(COALESCE(cls.count_final_48h, 0) * 100.0, cs.total_patients)
    - SAFE_DIVIDE(COALESCE(cls.count_first_12h, 0) * 100.0, cs.total_patients)
  ) AS net_change_pp
FROM all_drug_classes AS adc
CROSS JOIN cohort_stats AS cs
LEFT JOIN class_level_summary AS cls
  ON adc.drug_class = cls.drug_class
ORDER BY
  CASE adc.drug_class
    WHEN 'Insulin'
    THEN 1
    WHEN 'Metformin'
    THEN 2
    WHEN 'Sulfonylurea (SU)'
    THEN 3
    WHEN 'DPP-4 Inhibitor'
    THEN 4
    WHEN 'SGLT2 Inhibitor'
    THEN 5
    WHEN 'GLP-1 Agonist'
    THEN 6
    WHEN 'TZD'
    THEN 7
    ELSE 8
  END;