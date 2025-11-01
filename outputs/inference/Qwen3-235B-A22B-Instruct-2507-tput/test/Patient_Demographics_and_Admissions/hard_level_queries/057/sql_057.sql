WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    -- Compute age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit,
    -- LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 60 AND 70
    AND LOWER(a.admission_location) LIKE '%emergency%'
    AND LOWER(a.insurance) = 'medicare'
    AND a.dischtime IS NOT NULL
),

-- Join with diagnoses to find principal UTI diagnosis
cohort AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.los_days
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1  -- Principal diagnosis
    AND (
      LOWER(d.long_title) LIKE '%urinary tract infection%'
      OR LOWER(d.long_title) LIKE '%uti%'
      OR d.icd_code IN ('N390', 'B962', 'N10', 'N12', 'N30') -- Common UTI-related codes
    )
),

-- Get index admission (earliest) per patient
index_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    los_days,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
),
index_only AS (
  SELECT * FROM index_admissions WHERE rn = 1
),

-- Check for 30-day readmission
with_next_admit AS (
  SELECT
    ia.*,
    LEAD(ia.admittime) OVER (PARTITION BY ia.subject_id ORDER BY ia.admittime) AS next_admittime
  FROM index_only ia
),
readmission_flag AS (
  SELECT
    *,
    CASE
      WHEN next_admittime IS NOT NULL
       AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30
        THEN 1
      ELSE 0
    END AS thirty_day_readmit
  FROM with_next_admit
)

-- Final aggregation
SELECT
  thirty_day_readmit,
  COUNT(*) AS patient_count,
  -- 30-day readmission rate will be computed as % of total
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(100 * SUM(CASE WHEN los_days > 9 THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_los_gt_9_days
FROM readmission_flag
GROUP BY thirty_day_readmit
ORDER BY thirty_day_readmit;