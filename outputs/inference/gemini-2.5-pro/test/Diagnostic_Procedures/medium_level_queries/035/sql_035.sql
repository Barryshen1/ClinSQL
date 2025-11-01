WITH
  -- Step 1: Identify all hospital admissions with an AKI diagnosis and determine if it's primary or secondary.
  aki_diagnoses AS (
    SELECT
      hadm_id,
      -- An admission is 'Primary AKI' if any AKI diagnosis has seq_num = 1.
      -- We use MIN() to prioritize the 'Primary' classification.
      CASE
        WHEN MIN(CASE WHEN dx.seq_num = 1 THEN 1 ELSE 2 END) = 1
        THEN 'Primary AKI'
        ELSE 'Secondary AKI'
      END AS aki_type
    FROM
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    WHERE
      -- Filter for AKI diagnosis codes (ICD-9: 584.x, ICD-10: N17.x)
      (
        dx.icd_code LIKE '584%' AND dx.icd_version = 9
      )
      OR (
        dx.icd_code LIKE 'N17%' AND dx.icd_version = 10
      )
    GROUP BY
      hadm_id
  ),
  -- Step 2: Count the number of CT or MRI scans for each hospital admission.
  imaging_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_scans
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE
      -- Use LOWER() and LIKE for case-insensitive matching on procedure descriptions in BigQuery
      LOWER(short_description) LIKE '%ct%'
      OR LOWER(short_description) LIKE '%mri%'
      OR LOWER(short_description) LIKE '%magnetic resonance imaging%'
      OR LOWER(short_description) LIKE '%computed tomography%'
    GROUP BY
      hadm_id
  ),
  -- Step 3: Build the final cohort by filtering on age and calculating LOS.
  final_cohort AS (
    SELECT
      aki.hadm_id,
      adm.subject_id,
      aki.aki_type,
      -- Categorize length of stay into the specified groups.
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 1 AND 4
        THEN '1-4 days'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) BETWEEN 5 AND 7
        THEN '5-7 days'
        ELSE NULL
      END AS los_group
    FROM
      aki_diagnoses AS aki
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON aki.hadm_id = adm.hadm_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      -- Filter for patient age at admission between 43 and 53
      (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 43 AND 53
  )
-- Step 4: Join the cohort with scan counts and aggregate the final results.
SELECT
  fc.aki_type,
  fc.los_group,
  COUNT(DISTINCT fc.subject_id) AS patient_count,
  -- Use COALESCE to treat admissions with no scans as 0 for the average calculation.
  AVG(COALESCE(img.num_scans, 0)) AS mean_mri_ct_per_admission
FROM
  final_cohort AS fc
LEFT JOIN
  imaging_counts AS img
  ON fc.hadm_id = img.hadm_id
WHERE
  -- Exclude admissions that do not fall into the specified LOS groups.
  fc.los_group IS NOT NULL
GROUP BY
  fc.aki_type,
  fc.los_group
ORDER BY
  fc.aki_type,
  fc.los_group;