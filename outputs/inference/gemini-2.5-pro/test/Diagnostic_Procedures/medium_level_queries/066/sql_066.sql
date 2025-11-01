WITH
  -- Step 1: Identify female patients aged 88-98 with an asthma diagnosis
  asthma_patients AS (
    SELECT DISTINCT
      p.subject_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON p.subject_id = dx.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 88 AND 98
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '493%') -- ICD-9 for Asthma
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J45%') -- ICD-10 for Asthma
      )
  ),
  -- Step 2: Filter admissions for these patients by length of stay (LOS) and categorize
  admissions_with_los AS (
    SELECT
      adm.hadm_id,
      CASE
        WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 3
        THEN '1-3 days'
        WHEN CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 4 AND 7
        THEN '4-7 days'
      END AS los_category
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    JOIN
      asthma_patients AS ap
      ON adm.subject_id = ap.subject_id
    WHERE
      -- Filter for admissions with a LOS between 1 and 7 days inclusive
      CEIL(DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0) BETWEEN 1 AND 7
  ),
  -- Step 3: Count the number of diagnostic procedures for each admission
  procedure_counts AS (
    SELECT
      awl.hadm_id,
      awl.los_category,
      -- Count procedures for each admission. LEFT JOIN includes admissions with no procedures (count=0).
      COUNT(proc.icd_code) AS num_procedures
    FROM
      admissions_with_los AS awl
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON awl.hadm_id = proc.hadm_id
    GROUP BY
      awl.hadm_id,
      awl.los_category
  )
-- Step 4: Calculate the 25th, 50th, and 75th percentiles of procedure counts for each LOS group
SELECT
  los_category,
  -- APPROX_QUANTILES is efficient for calculating multiple percentiles.
  -- We ask for 4 quantiles to get the 25th (index 1), 50th (index 2), and 75th (index 3).
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(1)] AS percentile_25th,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(2)] AS percentile_50th,
  APPROX_QUANTILES(num_procedures, 4)[OFFSET(3)] AS percentile_75th
FROM
  procedure_counts
GROUP BY
  los_category
ORDER BY
  los_category;