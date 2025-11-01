with TIA: among women 88-98 with TIA, what's the median (IQR) CT/MRI studies per admission for 1-3 vs 4-7 day stays, stratified by ICU use?
-- The results are stratified by hospital length of stay (1-3 vs 4-7 days) and whether the patient had an ICU stay.

WITH
  -- CTE 1: Identify all relevant hospital admissions based on patient demographics and diagnosis.
  cohort_admissions AS (
    SELECT DISTINCT -- Use DISTINCT to prevent duplicating admissions if multiple TIA codes exist for one stay
      adm.hadm_id,
      -- Categorize length of stay (LOS) into the specified groups.
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 BETWEEN 1 AND 3
        THEN '1-3 days'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 > 3 AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 <= 7
        THEN '4-7 days'
        ELSE NULL
      END AS los_category,
      -- Flag admissions that included an ICU stay.
      CASE
        WHEN icu.hadm_id IS NOT NULL
        THEN 'ICU'
        ELSE 'No ICU'
      END AS icu_status
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    -- Join to get patient demographics (age, gender).
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    -- Join to filter for TIA diagnosis.
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
      ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
    -- Left join to check for an ICU stay during the admission.
    LEFT JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_icu.icustays`
    ) AS icu
      ON adm.hadm_id = icu.hadm_id
    WHERE
      pat.gender = 'F'
      -- Filter for patients aged 88-98 at admission.
      AND (
        pat.anchor_age + DATETIME_DIFF(adm.admittime, DATETIME(pat.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) BETWEEN 88 AND 98
      -- Filter for TIA diagnoses.
      AND d_dx.long_title LIKE '%Transient ischemic attack%'
  ),
  -- CTE 2: Count the number of CT/MRI procedures for each admission.
  imaging_counts AS (
    SELECT
      proc.hadm_id,
      COUNT(*) AS num_imaging_studies
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d_proc
      ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
    WHERE
      -- Identify CT and MRI procedures by their description.
      LOWER(d_proc.long_title) LIKE '%tomography%' OR LOWER(d_proc.long_title) LIKE '%magnetic resonance imaging%'
    GROUP BY
      proc.hadm_id
  ),
  -- CTE 3: Join cohort with imaging counts to create the final dataset for aggregation.
  final_data AS (
    SELECT
      ca.los_category,
      ca.icu_status,
      ca.hadm_id,
      -- If an admission has no imaging, its count is 0.
      COALESCE(ic.num_imaging_studies, 0) AS num_imaging_studies
    FROM cohort_admissions AS ca
    LEFT JOIN imaging_counts AS ic
      ON ca.hadm_id = ic.hadm_id
    WHERE
      -- Exclude admissions that do not fall into the specified LOS categories.
      ca.los_category IS NOT NULL
  )
-- Final aggregation to compute statistics for each stratum.
SELECT
  los_category,
  icu_status,
  COUNT(hadm_id) AS num_admissions,
  -- Calculate median (p50) and IQR (p75 - p25) using APPROX_QUANTILES.
  -- APPROX_QUANTILES(..., 4) returns an array: [min, p25, p50, p75, max]
  APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(2)] AS median_studies,
  (APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(3)] - APPROX_QUANTILES(num_imaging_studies, 4)[OFFSET(1)]) AS iqr_studies
FROM final_data
GROUP BY
  los_category,
  icu_status
ORDER BY
  los_category,
  icu_status;