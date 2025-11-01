WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    p.gender,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    -- Compute LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  -- Join to get principal diagnosis
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    -- Principal diagnosis
    di.seq_num = 1
    -- Ischemic stroke: ICD-10 codes I63.* or I64
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I63%' OR d.icd_code = 'I64')
    -- Male
    AND p.gender = 'M'
    -- Age 76-86 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    -- Medicare
    AND a.insurance = 'Medicare'
    -- Admitted from ED
    AND LOWER(a.admission_location) LIKE '%emergency%'
),
-- Now, for each admission, check if there is a readmission within 30 days
admissions_with_next AS (
  SELECT
    *,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM patient_admissions
),
cohort_with_readmission AS (
  SELECT
    hadm_id,
    los_days,
    -- Check if readmitted within 30 days
    CASE
      WHEN next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
        AND DATETIME_DIFF(next_admittime, dischtime, DAY) >= 0
        THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM admissions_with_next
)
-- Final aggregation
SELECT
  -- 30-day all-cause readmission rate
  AVG(readmitted_30d) AS readmission_rate,
  -- Median index LOS for readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median index LOS for non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
  -- Percent of index stays > 5 days
  AVG(CASE WHEN los_days > 5 THEN 1 ELSE 0 END) AS pct_index_stay_gt_5_days
FROM cohort_with_readmission;