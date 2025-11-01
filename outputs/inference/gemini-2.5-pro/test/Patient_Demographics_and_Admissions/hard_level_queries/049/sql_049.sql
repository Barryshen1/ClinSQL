WITH
  -- Step 1: Find all ICD codes related to Acute Kidney Injury/Failure.
  aki_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      LOWER(long_title) LIKE '%acute kidney failure%' OR LOWER(long_title) LIKE '%acute kidney injury%'
  ),
  -- Step 2: Identify the hospital admission IDs (hadm_id) for the specific cohort of interest (the "index" stays).
  index_hadm_ids AS (
    SELECT DISTINCT
      adm.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON adm.subject_id = p.subject_id
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN
      aki_codes AS aki
      ON dx.icd_code = aki.icd_code AND dx.icd_version = aki.icd_version
    WHERE
      -- Patient criteria
      p.gender = 'F'
      AND (DATETIME_DIFF(adm.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age) BETWEEN 61 AND 71
      -- Admission criteria
      AND adm.insurance = 'Medicare'
      AND adm.admission_location = 'SKILLED NURSING FACILITY'
      -- Diagnosis criteria
      AND dx.seq_num = 1 -- Principal diagnosis
  ),
  -- Step 3: For all patients, list their admissions and find the chronologically next admission time.
  all_admissions_with_next AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  -- Step 4: Filter to our index stays and calculate the LOS and readmission flag for each.
  index_stays_details AS (
    SELECT
      all_adm.hadm_id,
      DATETIME_DIFF(all_adm.dischtime, all_adm.admittime, DAY) AS index_los_days,
      -- A readmission is a new admission >0 and <=30 days after discharge.
      CASE
        WHEN DATETIME_DIFF(all_adm.next_admittime, all_adm.dischtime, DAY) > 0
          AND DATETIME_DIFF(all_adm.next_admittime, all_adm.dischtime, DAY) <= 30
          THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM all_admissions_with_next AS all_adm
    INNER JOIN
      index_hadm_ids AS ihi
      ON all_adm.hadm_id = ihi.hadm_id
  )
-- Step 5: Aggregate the results from the index stays to calculate the final metrics.
SELECT
  -- Metric 1: 30-day readmission rate
  SAFE_DIVIDE(SUM(is_readmitted_30d), COUNT(hadm_id)) * 100 AS readmission_rate_30_day,
  -- Metric 2: Median LOS for readmitted patients
  APPROX_QUANTILES(IF(is_readmitted_30d = 1, index_los_days, NULL), 2)[OFFSET(1)] AS median_los_readmitted,
  -- Metric 3: Median LOS for non-readmitted patients
  APPROX_QUANTILES(IF(is_readmitted_30d = 0, index_los_days, NULL), 2)[OFFSET(1)] AS median_los_non_readmitted,
  -- Metric 4: Percentage of stays longer than 6 days
  SAFE_DIVIDE(COUNTIF(index_los_days > 6), COUNT(hadm_id)) * 100 AS percent_stays_gt_6_days
FROM index_stays_details;