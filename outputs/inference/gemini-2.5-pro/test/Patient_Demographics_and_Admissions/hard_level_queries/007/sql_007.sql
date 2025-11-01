WITH tia_index_admissions AS (
  -- Step 1: Identify the cohort of index admissions based on the specified criteria.
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    -- Calculate age at admission and filter for the 83-93 range
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 83 AND 93
    -- Filter for the principal diagnosis
    AND dx.seq_num = 1
    -- Filter for TIA using both ICD-9 and ICD-10 codes
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '435%') OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'G45%')
    )
),

patient_admissions_ranked AS (
  -- Step 2: For each patient in the cohort, get their full admission history
  -- and find the next admission time to check for readmissions.
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Get the start time of the next admission for the same patient
    LEAD(a.admittime, 1) OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE a.subject_id IN (SELECT DISTINCT subject_id FROM tia_index_admissions)
),

cohort_with_metrics AS (
  -- Step 3: Filter back to the index TIA admissions and calculate LOS and readmission flag.
  SELECT
    par.hadm_id,
    -- Calculate the length of stay for the index admission in fractional days
    DATETIME_DIFF(par.dischtime, par.admittime, HOUR) / 24.0 AS index_los_days,
    -- Flag as 1 if the patient was readmitted within 30 days of discharge, otherwise 0
    CASE
      WHEN DATETIME_DIFF(par.next_admittime, par.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS readmitted_30_days
  FROM patient_admissions_ranked AS par
  -- We only care about the metrics for the original TIA admissions
  WHERE par.hadm_id IN (SELECT hadm_id FROM tia_index_admissions)
)

-- Step 4: Aggregate the results from the cohort to calculate the final metrics.
SELECT
  -- Metric 1: 30-day readmission rate
  AVG(readmitted_30_days) * 100 AS readmission_rate_30_day_percent,

  -- Metric 2: Median index LOS for readmitted vs non-readmitted patients
  APPROX_QUANTILES(
    CASE WHEN readmitted_30_days = 1 THEN index_los_days END, 100
  )[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(
    CASE WHEN readmitted_30_days = 0 THEN index_los_days END, 100
  )[OFFSET(50)] AS median_los_not_readmitted,

  -- Metric 3: Percent of index stays > 10 days
  AVG(CASE WHEN index_los_days > 10 THEN 1 ELSE 0 END) * 100 AS percent_stays_gt_10_days
FROM cohort_with_metrics;