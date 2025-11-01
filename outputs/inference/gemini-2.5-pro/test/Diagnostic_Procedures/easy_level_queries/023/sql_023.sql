WITH
  -- Step 1 & 2: Identify all hospital admissions for female patients aged 82-92
  patient_cohort_hadms AS (
    SELECT
      adm.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 82 AND 92
  ),
  -- Step 3: Define "cardiac" procedures by their ICD code description
  cardiac_proc_codes AS (
    SELECT DISTINCT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      LOWER(long_title) LIKE '%cardiac%'
  ),
  -- Step 4: Count the number of distinct cardiac procedures for each hospitalization in the cohort
  proc_counts_per_hadm AS (
    SELECT
      cohort.hadm_id,
      COUNT(DISTINCT cpc.icd_code) AS num_cardiac_procedures
    FROM
      patient_cohort_hadms AS cohort
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pro
      ON cohort.hadm_id = pro.hadm_id
    LEFT JOIN
      cardiac_proc_codes AS cpc
      ON pro.icd_code = cpc.icd_code AND pro.icd_version = cpc.icd_version
    GROUP BY
      cohort.hadm_id
  )
-- Step 5: Calculate the 25th percentile of the counts
SELECT
  APPROX_QUANTILES(num_cardiac_procedures, 100)[OFFSET(25)] AS p25_distinct_cardiac_procedures
FROM
  proc_counts_per_hadm;