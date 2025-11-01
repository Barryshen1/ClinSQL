WITH index_admissions AS (
  -- Step 1: Identify the specific cohort of "index" hospital admissions.
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate the length of stay in days for the index admission.
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON a.hadm_id = dx.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    p.gender = 'M'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM'
    -- The principal diagnosis is usually the one with the lowest sequence number
    AND dx.seq_num = 1
    -- Search for diagnosis description to be robust against different ICD versions/codes
    AND LOWER(d_dx.long_title) LIKE '%acute respiratory failure%'
    -- Calculate patient's age at the time of admission and filter for the 65-75 range
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 65 AND 75
),

patient_admissions_ranked AS (
  -- Step 2: For each patient in our cohort, find their next admission time.
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Use the LEAD window function to get the start time of the *next* admission for the same patient.
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  -- Optimization: only process admissions for patients who are in our index cohort.
  WHERE subject_id IN (SELECT DISTINCT subject_id FROM index_admissions)
),

cohort_with_readmission_flag AS (
  -- Step 3: Join the index admissions with their next admission time to flag 30-day readmissions.
  SELECT
    idx.hadm_id,
    idx.los_days,
    -- A 30-day readmission occurs if the next admission is within 30 days of the current discharge.
    CASE
      WHEN DATETIME_DIFF(pa.next_admittime, idx.dischtime, DAY) <= 30 THEN 1
      ELSE 0
    END AS is_readmitted_30_days
  FROM
    index_admissions AS idx
  LEFT JOIN
    patient_admissions_ranked AS pa
    ON idx.hadm_id = pa.hadm_id
)

-- Step 4: Aggregate the results to calculate the final metrics.
SELECT
  -- Metric 1: 30-day readmission rate (%)
  AVG(is_readmitted_30_days) * 100 AS readmission_rate_30_day,

  -- Metric 2: Median index LOS for readmitted vs. non-readmitted patients
  APPROX_QUANTILES(IF(is_readmitted_30_days = 1, los_days, NULL), 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(IF(is_readmitted_30_days = 0, los_days, NULL), 100)[OFFSET(50)] AS median_los_not_readmitted,

  -- Metric 3: Percent of index admissions with LOS > 9 days
  AVG(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) * 100 AS percent_los_gt_9_days
FROM
  cohort_with_readmission_flag;