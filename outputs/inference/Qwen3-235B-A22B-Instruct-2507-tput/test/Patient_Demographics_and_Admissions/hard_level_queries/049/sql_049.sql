WITH aki_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%acute kidney injury%'
     OR LOWER(long_title) LIKE '%acute renal failure%'
),
qualified_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    p.gender,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN aki_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  WHERE
    -- Principal diagnosis
    di.seq_num = 1
    -- Female
    AND p.gender = 'F'
    -- Age 61–71 at admission
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 61 AND 71
    -- Admission from SNF
    AND LOWER(a.admission_location) IN ('skilled nursing facility', 'snf')
    -- Insurance: Medicare
    AND LOWER(a.insurance) = 'medicare'
),
index_admissions AS (
  -- Rank admissions per patient to get the first (index) admission
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM qualified_admissions
),
index_stays AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM index_admissions
  WHERE rn = 1
),
readmission_flags AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.admittime,
    i.dischtime,
    i.los_days,
    -- Check if there's a readmission within 30 days
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = i.subject_id
          AND a2.admittime > i.dischtime
          AND a2.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30d
  FROM index_stays i
)
SELECT
  -- 30-day readmission rate
  AVG(CAST(readmitted_30d AS FLOAT64)) AS readmission_rate_30d,
  -- Median LOS for readmitted vs non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  APPROX_QUANTILES(CASE WHEN readmitted_30d = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_non_readmitted,
  -- Percent of index stays > 6 days
  AVG(CAST(los_days > 6 AS INT64)) AS pct_los_gt_6_days
FROM readmission_flags;