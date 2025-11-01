WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),

tia_admissions AS (
  SELECT
    pa.*
  FROM patient_ages pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    pa.age_at_admit BETWEEN 83 AND 93
    AND pa.gender = 'M'
    AND LOWER(pa.insurance) = 'medicare'
    AND (LOWER(pa.admission_location) LIKE '%ed%'
         OR LOWER(pa.admission_location) LIKE '%emergency department%')
    AND di.seq_num = 1
    AND LOWER(d.long_title) LIKE '%transient ischemic%'
),

index_admissions AS (
  -- Get the earliest (index) admission for each patient
  SELECT
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM tia_admissions
),

index_only AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    -- Compute LOS in days
    DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM index_admissions
  WHERE rn = 1
    AND dischtime IS NOT NULL  -- Must have discharge to assess readmission
),

readmission_flag AS (
  SELECT
    io.*,
    -- Check if there is a next admission within 30 days
    EXISTS(
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.admissions a_next
      WHERE a_next.subject_id = io.subject_id
        AND a_next.admittime > io.dischtime
        AND a_next.admittime <= DATETIME_ADD(io.dischtime, INTERVAL 30 DAY)
    ) AS readmitted_30d
  FROM index_only io
)

-- Final aggregation
SELECT
  -- 30-day readmission rate
  ROUND(AVG(CAST(readmitted_30d AS INT)) * 100, 2) AS readmission_rate_30d_pct,

  -- Median index LOS for readmitted vs non-readmitted
  ROUND(APPROX_QUANTILES(CASE WHEN readmitted_30d THEN los_days END, 2)[OFFSET(1)], 2) AS median_los_readmitted_days,
  ROUND(APPROX_QUANTILES(CASE WHEN NOT readmitted_30d THEN los_days END, 2)[OFFSET(1)], 2) AS median_los_nonreadmitted_days,

  -- Percent of index stays > 10 days
  ROUND(AVG(CAST(los_days > 10 AS INT)) * 100, 2) AS pct_los_gt_10_days

FROM readmission_flag;