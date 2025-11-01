WITH
  -- Step 1: Identify hospital admissions with both Diabetes and Acute Heart Failure
  hadm_with_conditions AS (
    SELECT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
    HAVING
      -- Patient has at least one diagnosis code for Diabetes
      COUNTIF(
        (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250')
        OR (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
      ) > 0
      AND
      -- Patient has at least one diagnosis code for Acute Heart Failure
      COUNTIF(
        icd_code IN (
          '428.0', '428.1', '428.21', '428.31', '428.41', -- ICD-9
          'I50.21', 'I50.31', 'I50.41' -- ICD-10
        )
      ) > 0
  ),
  -- Step 2: Filter the above admissions for male patients aged 42-52
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
    INNER JOIN hadm_with_conditions AS hwc ON adm.hadm_id = hwc.hadm_id
    WHERE
      pat.gender = 'M'
      AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 42 AND 52
  ),
  -- Step 3: Get the total count of patients in the final cohort for the denominator
  cohort_count AS (
    SELECT
      COUNT(hadm_id) AS total_hadms
    FROM
      cohort
  ),
  -- Step 4: Gather and classify all relevant drug administrations from both EMAR (ward) and InputEvents (ICU)
  drug_admins AS (
    -- Ward administrations from EMAR
    SELECT
      hadm_id,
      charttime AS admin_time,
      CASE
        WHEN LOWER(medication) LIKE '%insulin%' THEN 'Insulin'
        WHEN LOWER(medication) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(medication) LIKE '%glipizide%' OR LOWER(medication) LIKE '%glyburide%' OR LOWER(medication) LIKE '%glimepiride%' THEN 'Sulfonylurea'
        WHEN LOWER(medication) LIKE '%gliptin%' THEN 'DPP-4'
        WHEN LOWER(medication) LIKE '%gliflozin%' THEN 'SGLT2'
        WHEN LOWER(medication) LIKE '%glutide%' OR LOWER(medication) LIKE '%enatide%' THEN 'GLP-1'
        WHEN LOWER(medication) LIKE '%glitazone%' THEN 'TZD'
        ELSE NULL
      END AS drug_class
    FROM
      `physionet-data.mimiciv_3_1_hosp.emar`
    WHERE
      -- Filter for relevant drug administrations to reduce processing
      LOWER(medication) LIKE '%insul%'
      OR LOWER(medication) LIKE '%metform%'
      OR LOWER(medication) LIKE '%glip%'
      OR LOWER(medication) LIKE '%glyb%'
      OR LOWER(medication) LIKE '%glim%'
      OR LOWER(medication) LIKE '%glitaz%'
      OR LOWER(medication) LIKE '%glifloz%'
      OR LOWER(medication) LIKE '%glutide%'
      OR LOWER(medication) LIKE '%enatide%'
    UNION ALL
    -- ICU administrations from InputEvents
    SELECT
      inp.hadm_id,
      inp.starttime AS admin_time,
      CASE
        WHEN LOWER(di.label) LIKE '%insulin%' THEN 'Insulin'
        -- Other classes are oral and rarely in inputevents, but included for completeness
        WHEN LOWER(di.label) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(di.label) LIKE '%glipizide%' OR LOWER(di.label) LIKE '%glyburide%' OR LOWER(di.label) LIKE '%glimepiride%' THEN 'Sulfonylurea'
        WHEN LOWER(di.label) LIKE '%gliptin%' THEN 'DPP-4'
        WHEN LOWER(di.label) LIKE '%gliflozin%' THEN 'SGLT2'
        WHEN LOWER(di.label) LIKE '%glutide%' OR LOWER(di.label) LIKE '%enatide%' THEN 'GLP-1'
        WHEN LOWER(di.label) LIKE '%glitazone%' THEN 'TZD'
        ELSE NULL
      END AS drug_class
    FROM
      `physionet-data.mimiciv_3_1_icu.inputevents` AS inp
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON inp.itemid = di.itemid
    WHERE
      di.category LIKE 'Medications' AND (
        LOWER(di.label) LIKE '%insul%'
        OR LOWER(di.label) LIKE '%metform%'
        OR LOWER(di.label) LIKE '%glip%'
        OR LOWER(di.label) LIKE '%glyb%'
        OR LOWER(di.label) LIKE '%glim%'
        OR LOWER(di.label) LIKE '%glitaz%'
        OR LOWER(di.label) LIKE '%glifloz%'
        OR LOWER(di.label) LIKE '%glutide%'
        OR LOWER(di.label) LIKE '%enatide%'
      )
  ),
  -- Step 5: Link drug administrations to the cohort and categorize them by time window
  cohort_drug_admins AS (
    SELECT
      da.hadm_id,
      da.drug_class,
      CASE
        WHEN da.admin_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) THEN 'first_24h'
        WHEN da.admin_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 'final_12h'
        ELSE NULL
      END AS time_window
    FROM
      drug_admins AS da
    INNER JOIN cohort AS c ON da.hadm_id = c.hadm_id
    WHERE
      da.drug_class IS NOT NULL
      AND (
        da.admin_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
        OR da.admin_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
      )
  ),
  -- Step 6: Count unique patients for each drug class in each time window
  admin_counts AS (
    SELECT
      drug_class,
      COUNT(DISTINCT CASE WHEN time_window = 'first_24h' THEN hadm_id END) AS count_first_24h,
      COUNT(DISTINCT CASE WHEN time_window = 'final_12h' THEN hadm_id END) AS count_final_12h
    FROM
      cohort_drug_admins
    GROUP BY
      drug_class
  ),
  -- Step 7: Define all drug classes to ensure they all appear in the final output
  all_classes AS (
    SELECT 'Insulin' AS drug_class UNION ALL
    SELECT 'Metformin' AS drug_class UNION ALL
    SELECT 'Sulfonylurea' AS drug_class UNION ALL
    SELECT 'DPP-4' AS drug_class UNION ALL
    SELECT 'SGLT2' AS drug_class UNION ALL
    SELECT 'GLP-1' AS drug_class UNION ALL
    SELECT 'TZD' AS drug_class
  )
-- Final Step: Combine results, calculate percentages, and compute the net change
SELECT
  ac.drug_class,
  COALESCE(ROUND(COALESCE(adc.count_first_24h, 0) * 100.0 / NULLIF(cc.total_hadms, 0), 2), 0.00) AS prevalence_first_24h_pct,
  COALESCE(ROUND(COALESCE(adc.count_final_12h, 0) * 100.0 / NULLIF(cc.total_hadms, 0), 2), 0.00) AS prevalence_final_12h_pct,
  COALESCE(ROUND(
    (COALESCE(adc.count_final_12h, 0) * 100.0 / NULLIF(cc.total_hadms, 0)) - (COALESCE(adc.count_first_24h, 0) * 100.0 / NULLIF(cc.total_hadms, 0)),
    2
  ), 0.00) AS net_change_pp
FROM
  all_classes AS ac
LEFT JOIN admin_counts AS adc ON ac.drug_class = adc.drug_class
CROSS JOIN cohort_count AS cc
ORDER BY
  -- Custom order to match the likely importance/prevalence
  CASE
    WHEN ac.drug_class = 'Insulin' THEN 1
    WHEN ac.drug_class = 'Metformin' THEN 2
    WHEN ac.drug_class = 'Sulfonylurea' THEN 3
    WHEN ac.drug_class = 'DPP-4' THEN 4
    WHEN ac.drug_class = 'SGLT2' THEN 5
    WHEN ac.drug_class = 'GLP-1' THEN 6
    WHEN ac.drug_class = 'TZD' THEN 7
  END;