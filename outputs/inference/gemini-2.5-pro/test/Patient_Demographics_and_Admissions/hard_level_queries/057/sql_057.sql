WITH
-- Step 1: Identify the primary cohort of "index" admissions based on the specified criteria.
index_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON adm.hadm_id = dx.hadm_id
  WHERE
    -- Male patients aged 60-70
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 60 AND 70
    -- Admitted via ED with Medicare
    AND adm.admission_location = 'EMERGENCY ROOM'
    AND adm.insurance = 'Medicare'
    -- Principal diagnosis of UTI (ICD-9: 599.0, ICD-10: N39.0)
    AND dx.seq_num = 1
    AND dx.icd_code IN ('5990', 'N390')
),

-- Step 2: For each patient with an index admission, get their full admission history
-- and find the next admission time for each stay.
admission_sequences AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    -- Find the start time of the *next* admission for the same patient
    LEAD(adm.admittime, 1) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admit_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  -- Optimization: only consider patients who have at least one index admission
  WHERE adm.subject_id IN (SELECT DISTINCT subject_id FROM index_admissions)
),

-- Step 3: Filter the sequence to just our index admissions, then calculate the
-- length of stay (LOS) and flag if a 30-day readmission occurred.
index_stays_with_metrics AS (
  SELECT
    seq.hadm_id,
    -- Calculate the index length of stay in fractional days
    DATETIME_DIFF(seq.dischtime, seq.admittime, HOUR) / 24.0 AS index_los_days,
    -- Flag if a readmission occurred within 30 days of discharge
    CASE
      WHEN DATETIME_DIFF(seq.next_admit_time, seq.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS was_readmitted_30d
  FROM admission_sequences AS seq
  -- Restrict to only the previously identified index admissions
  INNER JOIN index_admissions AS idx
    ON seq.hadm_id = idx.hadm_id
)

-- Step 4: Aggregate the results to calculate the final report.
SELECT
  -- 30-day readmission rate as a percentage
  AVG(was_readmitted_30d) * 100 AS readmission_rate_30d_percent,

  -- Median LOS for patients who were readmitted
  APPROX_QUANTILES(
    IF(was_readmitted_30d = 1, index_los_days, NULL), 100
  )[OFFSET(50)] AS median_los_readmitted_days,

  -- Median LOS for patients who were not readmitted
  APPROX_QUANTILES(
    IF(was_readmitted_30d = 0, index_los_days, NULL), 100
  )[OFFSET(50)] AS median_los_not_readmitted_days,

  -- Percent of all index stays with LOS > 9 days
  AVG(CASE WHEN index_los_days > 9 THEN 1.0 ELSE 0.0 END) * 100 AS percent_los_gt_9_days
FROM index_stays_with_metrics;