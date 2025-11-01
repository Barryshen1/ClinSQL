WITH
-- Define age range (44-54) and female patients
female_44_54 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate age at admission (anchor_age is age at anchor_year)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 44 AND 54
),

-- Identify ICH patients (ICD-10 codes I61.x, I62.x)
ich_patients AS (
  SELECT DISTINCT
    f.subject_id,
    f.hadm_id,
    f.age_at_admission,
    f.admittime,
    f.dischtime,
    f.deathtime,
    f.hospital_expire_flag
  FROM
    female_44_54 f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'
),

-- Calculate APACHE II score (simplified example)
apache_ii_scores AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    -- Sum of APACHE II components (simplified; actual calculation would be more complex)
    SUM(CASE
      WHEN ce.itemid IN (223900, 223901) THEN ce.valuenum -- GCS components
      ELSE 0
    END) AS apache_ii_score
  FROM
    ich_patients i
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON i.hadm_id = ce.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.category = 'APACHE'
  GROUP BY
    i.subject_id, i.hadm_id
),

-- Calculate 90-day mortality
mortality_90d AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    CASE
      WHEN i.deathtime IS NOT NULL
        AND TIMESTAMP_DIFF(i.deathtime, i.admittime, DAY) <= 90
      THEN 1
      ELSE 0
    END AS died_within_90d
  FROM
    ich_patients i
),

-- Calculate LOS for survivors (pre-aggregated)
los_survivors AS (
  SELECT
    PERCENTILE_CONT(TIMESTAMP_DIFF(i.dischtime, i.admittime, DAY), 0.5) OVER() AS median_los_days
  FROM
    ich_patients i
  WHERE
    i.hospital_expire_flag = 0
  LIMIT 1
),

-- Comparison group: all female 44-54 inpatients
comparison_group AS (
  SELECT
    COUNT(DISTINCT f.subject_id) AS n_patients,
    AVG(CASE WHEN d.icd_code IN ('E11.65', 'I21.9') THEN 1 ELSE 0 END) * 100 AS major_complication_percent,
    PERCENTILE_CONT(TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY), 0.5) OVER() AS median_los_days
  FROM
    female_44_54 f
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
),

-- Risk score percentiles for comparison
risk_percentiles AS (
  SELECT
    PERCENTILE_CONT(apache_ii_score, 0.5) OVER() AS median_risk,
    PERCENTILE_CONT(apache_ii_score, 0.25) OVER() AS q1_risk,
    PERCENTILE_CONT(apache_ii_score, 0.75) OVER() AS q3_risk
  FROM
    apache_ii_scores
  LIMIT 1
),

-- Risk percentile calculation
risk_percentile AS (
  SELECT
    COUNT(*) AS total_patients,
    COUNT(CASE WHEN apache_ii_score <= (SELECT median_risk FROM risk_percentiles) THEN 1 END) AS patients_at_or_below_median
  FROM
    apache_ii_scores
)

-- Final results
SELECT
  -- ICH group metrics
  'ICH Group' AS cohort,
  COUNT(DISTINCT i.subject_id) AS n_patients,
  (SELECT median_risk FROM risk_percentiles) AS median_risk_score,
  (SELECT q1_risk FROM risk_percentiles) AS q1_risk_score,
  (SELECT q3_risk FROM risk_percentiles) AS q3_risk_score,
  AVG(m.died_within_90d) * 100 AS mortality_90d_percent,
  (SELECT median_los_days FROM los_survivors) AS median_los_survivors,

  -- Comparison group metrics
  'Comparison Group' AS comparison_cohort,
  (SELECT n_patients FROM comparison_group) AS n_comparison,
  (SELECT major_complication_percent FROM comparison_group) AS major_complication_percent,
  (SELECT median_los_days FROM comparison_group) AS median_los_comparison,

  -- Risk percentile
  (SELECT patients_at_or_below_median FROM risk_percentile) /
  (SELECT total_patients FROM risk_percentile) * 100 AS risk_percentile

FROM
  ich_patients i
JOIN
  apache_ii_scores a ON i.hadm_id = a.hadm_id
JOIN
  mortality_90d m ON i.hadm_id = m.hadm_id;