WITH patient_admissions AS (
  -- Step 1: Get all admissions for female Medicare patients aged 68–78 admitted from ED
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Room'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND (p.dod IS NULL OR a.admittime <= p.dod)  -- valid admission before death
),
-- Step 2: Filter for principal hemorrhagic stroke (seq_num = 1 and ICD code I61 or I62)
hemorrhagic_stroke AS (
  SELECT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND di.icd_version = 10
    AND (di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
),
-- Step 3: Combine and filter qualifying admissions
qualifying_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  INNER JOIN hemorrhagic_stroke hs
    ON pa.subject_id = hs.subject_id AND pa.hadm_id = hs.hadm_id
  WHERE pa.age_at_admit BETWEEN 68 AND 78
),
-- Step 4: Rank admissions per patient to get index admission
index_admissions AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM qualifying_admissions
),
index_only AS (
  SELECT *
  FROM index_admissions
  WHERE rn = 1  -- first (index) admission
),
-- Step 5: Check for 30-day readmission
readmission_flag AS (
  SELECT
    i.*,
    -- Check if there's any later admission within 30 days of discharge
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM qualifying_admissions qa
        WHERE qa.subject_id = i.subject_id
          AND qa.admittime > i.dischtime
          AND qa.admittime <= DATETIME_ADD(i.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmitted_30day
  FROM index_only i
)
-- Final aggregation
SELECT
  -- 30-day readmission rate
  ROUND(AVG(CAST(readmitted_30day AS FLOAT64)), 3) AS readmission_rate_30day,
  -- Median index LOS for readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30day = 1 THEN los_days END, 100)[OFFSET(50)] AS median_los_readmitted,
  -- Median index LOS for non-readmitted
  APPROX_QUANTILES(CASE WHEN readmitted_30day = 0 THEN los_days END, 100)[OFFSET(50)] AS median_los_nonreadmitted,
  -- % with index LOS > 4 days
  ROUND(
    AVG(CAST(los_days > 4 AS INT64)) * 100, 1
  ) AS pct_los_gt_4_days
FROM readmission_flag;