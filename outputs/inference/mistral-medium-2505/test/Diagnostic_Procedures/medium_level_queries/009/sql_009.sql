WITH
-- Select female patients aged 44-54
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 44 AND 54
),

-- Get admissions for these patients with LOS calculation
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = a.hadm_id
      ) THEN TRUE
      ELSE FALSE
    END AS had_icu_stay
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients fp ON a.subject_id = fp.subject_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count imaging events per admission (using HCPCS codes for imaging)
imaging_counts AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN
    admissions_with_los a ON h.hadm_id = a.hadm_id
  WHERE
    -- Filter for imaging-related HCPCS codes (example: codes starting with '7' or other imaging codes)
    h.hcpcs_cd LIKE '7%' OR
    h.hcpcs_cd IN ('70450', '70460', '70470', '70480', '70490', '70551', '70552', '70553') -- Example CT/MRI codes
  GROUP BY
    h.hadm_id
),

-- Combine all data and categorize LOS
final_data AS (
  SELECT
    a.hadm_id,
    a.los_days,
    a.had_icu_stay,
    CASE
      WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_category,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM
    admissions_with_los a
  LEFT JOIN
    imaging_counts i ON a.hadm_id = i.hadm_id
)

-- Calculate percentiles by LOS category and ICU use
SELECT
  los_category,
  had_icu_stay,
  COUNT(hadm_id) AS admission_count,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(imaging_count, 4)[OFFSET(3)] AS p75
FROM
  final_data
GROUP BY
  los_category, had_icu_stay
ORDER BY
  los_category, had_icu_stay;