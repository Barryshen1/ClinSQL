WITH
  -- Step 1: Find all ICD codes for 'Acute respiratory failure'
  arf_codes AS (
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      LOWER(long_title) LIKE '%acute respiratory failure%'
  ),
  -- Step 2: Get all admissions for all patients and find the next admission time for each
  all_patient_admissions AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ),
  -- Step 3: Identify the index admissions that meet the specific cohort criteria
  index_admissions AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    INNER JOIN arf_codes
      ON dx.icd_code = arf_codes.icd_code AND dx.icd_version = arf_codes.icd_version
    WHERE
      -- Principal diagnosis is Acute Respiratory Failure
      dx.seq_num = 1
      -- Female patients
      AND pat.gender = 'F'
      -- Admitted from a Skilled Nursing Facility
      AND adm.admission_location = 'SKILLED NURSING FACILITY'
      -- Insurance is Medicare
      AND adm.insurance = 'Medicare'
      -- Age at admission is between 77 and 87
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 77 AND 87
  ),
  -- Step 4: Combine index admissions with readmission data and calculate per-admission outcomes
  cohort_with_outcomes AS (
    SELECT
      idx.hadm_id,
      -- Calculate Length of Stay in days for the index admission
      DATETIME_DIFF(all_adm.dischtime, all_adm.admittime, DAY) AS index_los_days,
      -- Flag as 1 if a readmission occurred within 30 days of discharge, otherwise 0
      CASE
        WHEN all_adm.next_admittime IS NOT NULL AND all_adm.next_admittime <= DATETIME_ADD(all_adm.dischtime, INTERVAL 30 DAY)
          THEN 1
        ELSE 0
      END AS is_readmitted_30d
    FROM
      index_admissions AS idx
    INNER JOIN all_patient_admissions AS all_adm
      ON idx.hadm_id = all_adm.hadm_id
  )
-- Step 5: Aggregate the results to calculate the final metrics
SELECT
  -- Calculate the 30-day all-cause readmission rate
  AVG(is_readmitted_30d) * 100 AS readmission_rate_30d,
  -- Calculate median index LOS for patients who were readmitted
  APPROX_QUANTILES(
    IF(is_readmitted_30d = 1, index_los_days, NULL), 100
  )[OFFSET(50)] AS median_los_readmitted,
  -- Calculate median index LOS for patients who were NOT readmitted
  APPROX_QUANTILES(
    IF(is_readmitted_30d = 0, index_los_days, NULL), 100
  )[OFFSET(50)] AS median_los_not_readmitted,
  -- Calculate the percentage of index stays that were longer than 8 days
  AVG(IF(index_los_days > 8, 1, 0)) * 100 AS percent_index_los_gt_8_days
FROM
  cohort_with_outcomes;