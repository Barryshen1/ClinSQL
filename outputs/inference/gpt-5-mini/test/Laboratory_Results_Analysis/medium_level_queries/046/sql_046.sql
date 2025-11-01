WITH troponin_items AS (
  -- identify Troponin T lab itemids (case-insensitive match)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

cohort_admissions AS (
  -- admissions for male patients aged 83-93 that have a diagnosis of AMI or chest pain
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON dx.icd_code = ddi.icd_code
    AND dx.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND (
      LOWER(ddi.long_title) LIKE '%myocardial infarction%'
      OR LOWER(ddi.long_title) LIKE '%chest pain%'
    )
),

initial_troponin AS (
  -- first (earliest) troponin T measurement per admission (hadm_id)
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM (
    SELECT
      le.*,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.storetime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN troponin_items ti
      ON le.itemid = ti.itemid
    WHERE le.valuenum IS NOT NULL
      -- restrict to labs that belong to cohort admissions
      AND le.hadm_id IN (SELECT hadm_id FROM cohort_admissions)
  ) le
  WHERE rn = 1
),

trop_stats AS (
  -- compute the 99th percentile threshold across initial troponin values (for admissions in the cohort)
  SELECT
    APPROX_QUANTILES(valuenum, 100)[OFFSET(99)] AS trop_99pct
  FROM initial_troponin
)

SELECT
  COUNT(DISTINCT ca.hadm_id) AS n_admissions,
  COUNT(DISTINCT ca.subject_id) AS n_distinct_patients,
  -- mean patient age (anchor_age)
  ROUND(AVG(ca.anchor_age), 2) AS mean_age_years,
  -- mean hospital LOS in days
  ROUND(AVG(TIMESTAMP_DIFF(ca.dischtime, ca.admittime, MINUTE) / 1440.0), 2) AS mean_los_days,
  -- troponin measurement summaries
  SUM(CASE WHEN it.valuenum IS NOT NULL THEN 1 ELSE 0 END) AS n_with_initial_troponin,
  ROUND(AVG(it.valuenum), 4) AS mean_initial_troponin,
  -- approximate median
  (SELECT APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] FROM initial_troponin) AS median_initial_troponin,
  ROUND(STDDEV_SAMP(it.valuenum), 4) AS sd_initial_troponin,
  MIN(it.valuenum) AS min_initial_troponin,
  MAX(it.valuenum) AS max_initial_troponin,
  -- 99th percentile threshold and counts above it (referenced via scalar subquery)
  (SELECT trop_99pct FROM trop_stats) AS initial_troponin_99pct_threshold,
  SUM(CASE WHEN it.valuenum IS NOT NULL AND it.valuenum > (SELECT trop_99pct FROM trop_stats) THEN 1 ELSE 0 END) AS n_initial_trop_above_99pct,
  ROUND(100.0 * SUM(CASE WHEN it.valuenum IS NOT NULL AND it.valuenum > (SELECT trop_99pct FROM trop_stats) THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN it.valuenum IS NOT NULL THEN 1 ELSE 0 END), 0), 2) AS pct_initial_trop_above_99pct
FROM cohort_admissions ca
LEFT JOIN initial_troponin it
  ON ca.hadm_id = it.hadm_id;