WITH
  -- Create a cohort of male patients aged 49-59 with a primary diagnosis of heart failure.
  cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON p.subject_id = adm.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'M'
      -- Calculate age at admission and filter for the 49-59 range.
      AND ((EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age) BETWEEN 49 AND 59
      -- Filter for primary diagnosis (seq_num=1) of Heart Failure (ICD-9: 428.x, ICD-10: I50.x)
      AND dx.seq_num = 1
      AND (
        dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%'
      )
  ),
  -- Count the number of CT/MRI procedures for each hospital admission.
  imaging_counts AS (
    SELECT
      hcpcs.hadm_id,
      COUNT(*) AS num_scans
    FROM
      `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcpcs
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.d_hcpcs` AS d_hcpcs
      ON hcpcs.hcpcs_cd = d_hcpcs.code
    WHERE
      -- Use descriptions to identify CT, MRI, and MRA procedures.
      UPPER(d_hcpcs.long_description) LIKE '%COMPUTED TOMOGRAPHY%'
      OR UPPER(d_hcpcs.long_description) LIKE '%MAGNETIC RESONANCE IMAGING%'
      OR UPPER(d_hcpcs.long_description) LIKE '%MAGNETIC RESONANCE ANGIOGRAPHY%'
    GROUP BY
      hcpcs.hadm_id
  ),
  -- Identify hospital admissions that included an ICU stay.
  icu_admissions AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  -- Combine all data and prepare for final aggregation.
  final_data AS (
    SELECT
      c.hadm_id,
      -- Calculate length of stay in days.
      CEIL(DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0) AS los_days,
      -- Flag admissions with an ICU stay.
      CASE
        WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
        ELSE 'Non-ICU'
      END AS icu_use,
      -- Use 0 for admissions with no imaging procedures.
      COALESCE(img.num_scans, 0) AS num_scans
    FROM
      cohort AS c
    LEFT JOIN
      imaging_counts AS img
      ON c.hadm_id = img.hadm_id
    LEFT JOIN
      icu_admissions AS icu
      ON c.hadm_id = icu.hadm_id
  )
-- Final query to stratify, group, and calculate the required metrics.
SELECT
  -- Create the Length of Stay groups for stratification.
  CASE
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_group,
  icu_use,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(num_scans) AS mean_ct_mri_per_admission
FROM
  final_data
WHERE
  -- Filter for only the LOS groups of interest.
  los_days BETWEEN 1 AND 7
GROUP BY
  los_group,
  icu_use
ORDER BY
  los_group,
  icu_use DESC;