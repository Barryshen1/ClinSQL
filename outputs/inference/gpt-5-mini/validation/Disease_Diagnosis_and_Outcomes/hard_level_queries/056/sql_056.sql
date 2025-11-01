WITH
-- Aggregate diagnoses per admission, and set flags for septic shock and major complications
diag_summary AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diag_count,
    MAX(IF(LOWER(d.long_title) LIKE '%septic shock%', 1, 0)) AS has_septic_shock,
    -- major complication if any diagnosis title matches common serious complications
    MAX(
      IF(
        REGEXP_CONTAINS(
          LOWER(d.long_title),
          '(acute respiratory failure|acute respiratory distress|acute renal failure|acute kidney injury|myocardial infarction|acute myocardial infarction|cerebrovascular accident|stroke|pulmonary emboli|pulmonary embolism|cardiac arrest)'
        ),
        1,
        0
      )
    ) AS has_major_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  GROUP BY
    di.subject_id,
    di.hadm_id
),

-- Join admissions/patients to the diag summary and compute LOS & 90-day death flag
adm_with_flags AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    -- integer days LOS
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    COALESCE(ds.diag_count, 0) AS diag_count,
    COALESCE(ds.has_septic_shock, 0) AS has_septic_shock,
    COALESCE(ds.has_major_complication, 0) AS has_major_complication,
    a.hospital_expire_flag,
    p.dod,
    -- death within 90 days: in-hospital OR recorded date of death within 90 days after discharge
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      WHEN p.dod IS NOT NULL AND DATE(p.dod) <= DATE_ADD(DATE(a.dischtime), INTERVAL 90 DAY) THEN 1
      ELSE 0
    END AS death_within_90
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  LEFT JOIN
    diag_summary ds
  ON
    a.hadm_id = ds.hadm_id
  WHERE
    a.dischtime IS NOT NULL  -- exclude incomplete stays
),

-- Metrics for the target cohort: male, age 63-73 (inclusive), septic shock, >15 diagnoses
cohort_metrics AS (
  SELECT
    COUNT(1) AS n_admissions,
    AVG(diag_count) AS mean_diag_count_proxy,
    AVG(CAST(death_within_90 AS FLOAT64)) AS mortality_90d,
    AVG(CAST(has_major_complication AS FLOAT64)) AS major_complication_rate,
    -- mean LOS among survivors (death_within_90 = 0). NULL if no survivors.
    AVG(CASE WHEN death_within_90 = 0 THEN los_days END) AS survivor_mean_los_days
  FROM
    adm_with_flags
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 63 AND 73
    AND has_septic_shock = 1
    AND diag_count > 15
),

-- Metrics for general adult inpatients (comparator)
general_metrics AS (
  SELECT
    COUNT(1) AS n_admissions,
    AVG(diag_count) AS mean_diag_count_proxy,
    AVG(CAST(death_within_90 AS FLOAT64)) AS mortality_90d,
    AVG(CAST(has_major_complication AS FLOAT64)) AS major_complication_rate,
    AVG(CASE WHEN death_within_90 = 0 THEN los_days END) AS survivor_mean_los_days
  FROM
    adm_with_flags
  WHERE
    anchor_age >= 18
),

-- Percentile calculations for diag_count = 16 (profile with 16 diagnoses)
percentiles AS (
  SELECT
    -- among all adult inpatients
    100.0 * SUM(CASE WHEN diag_count <= 16 THEN 1 ELSE 0 END) / COUNT(1) AS percentile_diagcount_le_16_among_adults,
    -- among males aged 63-73
    100.0 * SUM(CASE WHEN gender = 'M' AND anchor_age BETWEEN 63 AND 73 AND diag_count <= 16 THEN 1 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN gender = 'M' AND anchor_age BETWEEN 63 AND 73 THEN 1 ELSE 0 END), 0) AS percentile_diagcount_le_16_males_63_73
  FROM
    adm_with_flags
  WHERE
    anchor_age >= 18
)

-- Final output: one-row summary with cohort + general comparator + percentiles
SELECT
  cm.n_admissions AS cohort_n_admissions,
  cm.mean_diag_count_proxy AS cohort_mean_risk_score_proxy_diag_count,
  cm.mortality_90d AS cohort_90d_mortality_rate,
  cm.major_complication_rate AS cohort_major_complication_rate,
  cm.survivor_mean_los_days AS cohort_mean_survivor_los_days,
  gm.n_admissions AS general_n_admissions,
  gm.mean_diag_count_proxy AS general_mean_risk_score_proxy_diag_count,
  gm.mortality_90d AS general_90d_mortality_rate,
  gm.major_complication_rate AS general_major_complication_rate,
  gm.survivor_mean_los_days AS general_mean_survivor_mean_los_days,
  p.percentile_diagcount_le_16_among_adults,
  p.percentile_diagcount_le_16_males_63_73
FROM
  cohort_metrics cm,
  general_metrics gm,
  percentiles p;