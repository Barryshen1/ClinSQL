WITH
  -- 1. Count diagnostic imaging procedures for each hospital admission
  proc_counts AS (
    SELECT
      hadm_id,
      COUNT(*) AS num_imaging_procedures
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE
      -- ICD-9 codes for diagnostic imaging (e.g., ultrasound, CT, MRI)
      (icd_version = 9 AND SUBSTR(icd_code, 1, 2) IN ('87', '88'))
      -- ICD-10 codes for imaging start with 'B'
      OR (icd_version = 10 AND SUBSTR(icd_code, 1, 1) = 'B')
    GROUP BY
      hadm_id
  ),

  -- 2. Identify all hospital admissions that included an ICU stay
  icu_adms AS (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- 3. Define the main patient cohort based on demographics and length of stay
  admissions_cohort AS (
    SELECT
      a.hadm_id,
      CASE
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      END AS los_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      -- Filter for age at admission between 72 and 82
      AND (
        p.anchor_age + DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
      ) BETWEEN 72 AND 82
      -- Filter for total hospital LOS between 1 and 7 days
      AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
  )

-- 4. Final aggregation to compute metrics by LOS category and ICU use
SELECT
  cohort.los_category,
  CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_use,
  COUNT(DISTINCT cohort.hadm_id) AS admission_count,
  AVG(COALESCE(proc.num_imaging_procedures, 0)) AS mean_imaging_procedures
FROM
  admissions_cohort AS cohort
LEFT JOIN
  icu_adms AS icu
  ON cohort.hadm_id = icu.hadm_id
LEFT JOIN
  proc_counts AS proc
  ON cohort.hadm_id = proc.hadm_id
GROUP BY
  cohort.los_category,
  icu_use
ORDER BY
  cohort.los_category,
  icu_use;