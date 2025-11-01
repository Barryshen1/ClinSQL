WITH troponin_items AS (
  -- Find candidate Troponin T lab itemids dynamically
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'    -- target Troponin T entries
     OR LOWER(label) LIKE '%troponin-t%'
     OR LOWER(label) LIKE '%troponin t,%'    -- some labels have punctuation
),

acs_admissions AS (
  -- Admissions for male patients age 79-89 with diagnoses consistent with ACS
  SELECT DISTINCT adm.subject_id,
         adm.hadm_id,
         adm.admittime,
         adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON adm.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
   AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    -- textual search to capture MI / unstable angina / ACS diagnoses
    AND (
         LOWER(d.long_title) LIKE '%myocardial infarction%'
      OR LOWER(d.long_title) LIKE '%acute myocardial%'
      OR LOWER(d.long_title) LIKE '%unstable angina%'
      OR LOWER(d.long_title) LIKE '%acute coronary syndrome%'
    )
),

initial_troponin AS (
  -- Find the earliest Troponin T lab per admission (after admittime)
  SELECT
    a.subject_id,
    a.hadm_id,
    le.itemid,
    le.charttime,
    le.valuenum,
    le.valueuom,
    le.flag,
    le.ref_range_lower,
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM acs_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.charttime >= a.admittime    -- initial after admission time
    AND le.valuenum IS NOT NULL         -- need numeric value for statistics
),

first_troponin_per_adm AS (
  -- take only the first troponin per admission
  SELECT *
  FROM initial_troponin
  WHERE rn = 1
),

categorized AS (
  -- categorize troponin value using ref_range_upper when available,
  -- fallback to flag-based classification when ref_range_upper is missing.
  SELECT
    f.subject_id,
    f.hadm_id,
    f.valuenum,
    f.ref_range_upper,
    f.flag,
    CASE
      WHEN f.valuenum IS NULL THEN NULL
      WHEN f.ref_range_upper IS NOT NULL AND f.valuenum <= f.ref_range_upper THEN 'normal'
      WHEN f.ref_range_upper IS NOT NULL
           AND f.valuenum > f.ref_range_upper
           AND f.valuenum <= (2 * f.ref_range_upper) THEN 'borderline'
      WHEN f.ref_range_upper IS NOT NULL
           AND f.valuenum > (2 * f.ref_range_upper) THEN 'elevated'
      WHEN f.ref_range_upper IS NULL
           AND LOWER(COALESCE(f.flag, '')) IN ('h','hh','high','abnormal','abnormal high','abnormal high?') THEN 'elevated'
      WHEN f.ref_range_upper IS NULL
           THEN 'normal'
      ELSE 'unknown'
    END AS troponin_category
  FROM first_troponin_per_adm f
),

counts_and_stats AS (
  -- compute total count (with an initial troponin) and per-category summaries
  SELECT
    troponin_category,
    COUNT(1) AS n,
    ROUND(100.0 * COUNT(1) / SUM(COUNT(1)) OVER (), 2) AS pct_of_cohort_with_troponin,
    AVG(valuenum) AS mean_troponin,
    -- APPROX_QUANTILES with 4 quantiles returns 5 values: min, Q1, median, Q3, max
    -- We extract Q1, median, Q3 and compute IQR
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(1)] AS q1,
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(2)] AS median,
    (APPROX_QUANTILES(valuenum, 4))[OFFSET(3)] AS q3
  FROM categorized
  WHERE troponin_category IS NOT NULL
  GROUP BY troponin_category
)

SELECT
  troponin_category,
  n,
  pct_of_cohort_with_troponin,
  mean_troponin,
  median,
  q1,
  q3,
  (q3 - q1) AS iqr
FROM counts_and_stats
ORDER BY
  -- order by severity: normal, borderline, elevated
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
    ELSE 4
  END;