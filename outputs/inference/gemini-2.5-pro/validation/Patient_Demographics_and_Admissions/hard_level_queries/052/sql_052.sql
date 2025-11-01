WITH index_admissions AS (
  -- Step 1: Identify the specific cohort of hospital admissions.
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND adm.insurance = 'Medicare'
    AND adm.admission_location = 'EMERGENCY DEPARTMENT'
    AND dx.seq_num = 1 -- Filter for principal diagnosis
    AND (
      dx.icd_code = '5770' -- ICD-9 for Acute Pancreatitis
      OR dx.icd_code LIKE 'K85%' -- ICD-10 for Acute Pancreatitis
    )
),

cohort_with_metrics AS (
  -- Step 2: For each index admission, calculate LOS and check for 30-day readmission.
  SELECT
    ia.hadm_id,
    -- Calculate length of stay in fractional days
    DATETIME_DIFF(ia.dischtime, ia.admittime, HOUR) / 24.0 AS los_days,
    -- Flag admissions that are followed by another admission within 30 days
    (
      EXISTS (
        SELECT
          1
        FROM
          `physionet-data.mimiciv_3_1_hosp.admissions` AS next_adm
        WHERE
          next_adm.subject_id = ia.subject_id
          AND next_adm.admittime > ia.dischtime
          AND DATETIME_DIFF(next_adm.admittime, ia.dischtime, DAY) <= 30
      )
    ) AS is_readmitted_30_days
  FROM
    index_admissions AS ia
)

-- Step 3: Aggregate the metrics to answer the question.
SELECT
  -- 30-day readmission rate
  AVG(
    CASE
      WHEN is_readmitted_30_days
      THEN 1.0
      ELSE 0.0
    END
  ) * 100 AS readmission_rate_30_day_percent,

  -- Median index LOS for readmitted vs non-readmitted patients
  APPROX_QUANTILES(
    CASE
      WHEN is_readmitted_30_days
      THEN los_days
    END, 2
  )[
  OFFSET
    (1)] AS median_los_readmitted,
  APPROX_QUANTILES(
    CASE
      WHEN NOT is_readmitted_30_days
      THEN los_days
    END, 2
  )[
  OFFSET
    (1)] AS median_los_non_readmitted,

  -- Percent of stays longer than 9 days
  AVG(
    CASE
      WHEN los_days > 9
      THEN 1.0
      ELSE 0.0
    END
  ) * 100 AS percent_stays_gt_9_days
FROM
  cohort_with_metrics;