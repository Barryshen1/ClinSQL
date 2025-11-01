WITH
-- Define age range and gender filter
female_55_65 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

-- Define lab instability components (example itemids - these would need validation)
lab_components AS (
  SELECT
    itemid,
    label,
    CASE
      WHEN label LIKE '%WBC%' THEN 'wbc'
      WHEN label LIKE '%Sodium%' THEN 'sodium'
      WHEN label LIKE '%Potassium%' THEN 'potassium'
      WHEN label LIKE '%Glucose%' THEN 'glucose'
      WHEN label LIKE '%Creatinine%' THEN 'creatinine'
      WHEN label LIKE '%pH%' THEN 'ph'
      ELSE NULL
    END AS component_type,
    -- Define normal ranges (these are example values - would need clinical validation)
    CASE
      WHEN label LIKE '%WBC%' THEN STRUCT(4.0 AS lower, 11.0 AS upper)
      WHEN label LIKE '%Sodium%' THEN STRUCT(135.0 AS lower, 145.0 AS upper)
      WHEN label LIKE '%Potassium%' THEN STRUCT(3.5 AS lower, 5.0 AS upper)
      WHEN label LIKE '%Glucose%' THEN STRUCT(70.0 AS lower, 140.0 AS upper)
      WHEN label LIKE '%Creatinine%' THEN STRUCT(0.5 AS lower, 1.2 AS upper)
      WHEN label LIKE '%pH%' THEN STRUCT(7.35 AS lower, 7.45 AS upper)
      ELSE NULL
    END AS normal_range
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    label LIKE '%WBC%'
    OR label LIKE '%Sodium%'
    OR label LIKE '%Potassium%'
    OR label LIKE '%Glucose%'
    OR label LIKE '%Creatinine%'
    OR label LIKE '%pH%'
),

-- Get lab results within first 48 hours
early_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    lc.component_type,
    lc.normal_range
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    lab_components lc ON l.itemid = lc.itemid
  JOIN
    female_55_65 f ON l.subject_id = f.subject_id AND l.hadm_id = f.hadm_id
  WHERE
    TIMESTAMP_DIFF(l.charttime, f.admittime, HOUR) BETWEEN 0 AND 48
    AND l.valuenum IS NOT NULL
),

-- Calculate abnormality scores for each lab component
abnormality_scores AS (
  SELECT
    subject_id,
    hadm_id,
    component_type,
    COUNT(*) AS component_count,
    SUM(
      CASE
        WHEN valuenum < normal_range.lower THEN 1
        WHEN valuenum > normal_range.upper THEN 1
        ELSE 0
      END
    ) AS abnormal_count
  FROM
    early_labs
  GROUP BY
    subject_id, hadm_id, component_type
),

-- Calculate overall instability score per patient
instability_scores AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.los_hours,
    f.hospital_expire_flag,
    SUM(a.abnormal_count) AS total_abnormal,
    COUNT(DISTINCT a.component_type) AS components_measured,
    SUM(a.abnormal_count) / COUNT(DISTINCT a.component_type) AS instability_score
  FROM
    female_55_65 f
  LEFT JOIN
    abnormality_scores a ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
  GROUP BY
    f.subject_id, f.hadm_id, f.los_hours, f.hospital_expire_flag
),

-- Calculate 95th percentile of instability score
percentile_cutoff AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95
  FROM
    instability_scores
  LIMIT 1
),

-- Get top tier patients (above 95th percentile)
top_tier AS (
  SELECT
    i.*
  FROM
    instability_scores i
  CROSS JOIN
    percentile_cutoff p
  WHERE
    i.instability_score >= p.p95
),

-- General inpatient population for comparison
general_population AS (
  SELECT
    COUNT(*) AS total_patients,
    AVG(los_hours) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate
  FROM
    female_55_65
)

-- Final results
SELECT
  'Top Tier (95th percentile)' AS group_name,
  COUNT(*) AS patient_count,
  AVG(los_hours) AS avg_los_hours,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS total_deaths,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(instability_score) AS avg_instability_score,
  MAX(g.total_patients) AS general_pop_total,
  MAX(g.avg_los) AS general_avg_los,
  MAX(g.mortality_rate) AS general_mortality_rate
FROM
  top_tier
CROSS JOIN
  general_population g
UNION ALL
SELECT
  'General Population' AS group_name,
  g.total_patients,
  g.avg_los,
  g.total_deaths,
  g.mortality_rate,
  NULL AS avg_instability_score,
  NULL AS general_pop_total,
  NULL AS general_avg_los,
  NULL AS general_mortality_rate
FROM
  general_population g;