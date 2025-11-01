WITH
  asthma_admissions AS (
    -- Step 1: Identify all hospital admissions for the target patient cohort and LOS.
    -- Cohort: Males, 77-87 years old, with a diagnosis of asthma exacerbation.
    -- LOS: Hospital stay between 1 and 8 days.
    SELECT DISTINCT
      a.hadm_id,
      CASE
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4
        THEN '1-4 days'
        ELSE '5-8 days'
      END AS los_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON a.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 77 AND 87
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
      AND (
        -- ICD-9 codes for asthma with acute exacerbation (e.g., 493.02, 493.12, ...)
        (dx.icd_version = 9 AND dx.icd_code IN ('49302', '49312', '49322', '49392'))
        -- ICD-10 codes for asthma with acute exacerbation (e.g., J45.21, J45.901, ...)
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J45%1')
      )
  ),
  scan_counts AS (
    -- Step 2: Count the number of CT or MRI scans for each hospital admission.
    -- We use hcpcsevents, which records procedures for billing.
    SELECT
      hadm_id,
      COUNT(hcpcs_cd) AS num_scans
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
      -- Filter for descriptions indicating a CT or MRI scan.
      LOWER(short_description) LIKE 'ct %' OR LOWER(short_description) LIKE 'mri %'
    GROUP BY
      hadm_id
  ),
  icu_admissions AS (
    -- Step 3: Identify all hospital admissions that included an ICU stay.
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  )
-- Step 4: Combine the data and calculate final statistics.
SELECT
  aa.los_category,
  CASE
    WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
    ELSE 'Non-ICU'
  END AS icu_status,
  COUNT(aa.hadm_id) AS num_admissions,
  -- Use COALESCE to treat admissions with no scans as having 0 scans.
  -- This is crucial for correct mean, min, and max calculations.
  AVG(COALESCE(sc.num_scans, 0)) AS mean_scans_per_admission,
  MIN(COALESCE(sc.num_scans, 0)) AS min_scans_per_admission,
  MAX(COALESCE(sc.num_scans, 0)) AS max_scans_per_admission
FROM
  asthma_admissions AS aa
LEFT JOIN
  icu_admissions AS icu ON aa.hadm_id = icu.hadm_id
LEFT JOIN
  scan_counts AS sc ON aa.hadm_id = sc.hadm_id
GROUP BY
  los_category,
  icu_status
ORDER BY
  icu_status,
  los_category;