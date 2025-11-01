WITH cohort AS (
  -- HHS cohort: female, 50-60, with HHS diagnosis
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND (
      (di.icd_version = 10 AND di.icd_code IN ('E11.00', 'E10.00', 'E13.00', 'E14.00'))
      OR (di.icd_version = 9 AND di.icd_code IN ('25020', '25022', '25023'))
    )
),

glucose_first AS (
  -- First glucose within 48h
  SELECT 
    l.hadm_id,
    l.valuenum AS first_glucose
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.itemid IN (50931, 50809, 225624, 226537)
    AND l.valuenum IS NOT NULL 
    AND l.valuenum > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) = 1
),

sodium_first AS (
  -- First sodium within 48h
  SELECT 
    l.hadm_id,
    l.valuenum AS first_sodium
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.itemid = 50824
    AND l.valuenum IS NOT NULL 
    AND l.valuenum > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) = 1
),

bun_first AS (
  -- First BUN within 48h
  SELECT 
    l.hadm_id,
    l.valuenum AS first_bun
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.itemid = 51006
    AND l.valuenum IS NOT NULL 
    AND l.valuenum > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) = 1
),

scores AS (
  -- Compute osmolarity score (only if all labs present)
  SELECT 
    c.hadm_id,
    c.admittime,
    (2 * s.first_sodium + g.first_glucose / 18.0 + b.first_bun / 2.8) AS osm_score
  FROM cohort c
  JOIN glucose_first g ON c.hadm_id = g.hadm_id
  JOIN sodium_first s ON c.hadm_id = s.hadm_id
  JOIN bun_first b ON c.hadm_id = b.hadm_id
),

threshold_cte AS (
  SELECT PERCENTILE_CONT(osm_score, 0.75) AS thresh
  FROM scores
),

high_scores AS (
  SELECT s.*
  FROM scores s, threshold_cte t
  WHERE s.osm_score >= t.thresh
),

general_cohort AS (
  -- General female 50-60 inpatients (no diagnosis filter)
  SELECT DISTINCT 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
),

stats AS (
  -- Mortality and mean LOS for high-score subgroup
  SELECT 
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0) AS mean_los_days
  FROM high_scores hs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON hs.hadm_id = a.hadm_id
),

has_critical_hhs AS (
  -- Indicator for critical labs (≥1 abnormal flag) in high-score subgroup, first 48h
  SELECT 
    hs.hadm_id,
    CASE WHEN COUNT(l.labevent_id) > 0 THEN 1 ELSE 0 END AS has_critical
  FROM high_scores hs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON hs.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY hs.hadm_id
),

has_critical_general AS (
  -- Same for general cohort
  SELECT 
    gc.hadm_id,
    CASE WHEN COUNT(l.labevent_id) > 0 THEN 1 ELSE 0 END AS has_critical
  FROM general_cohort gc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON gc.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY gc.hadm_id
)

-- Final output
SELECT 
  t.thresh AS p75_threshold,
  s.mortality,
  s.mean_los_days,
  (SELECT AVG(CAST(has_critical AS FLOAT64)) FROM has_critical_hhs) AS critical_lab_rate_hhs_high,
  (SELECT AVG(CAST(has_critical AS FLOAT64)) FROM has_critical_general) AS critical_lab_rate_general
FROM threshold_cte t, stats s;