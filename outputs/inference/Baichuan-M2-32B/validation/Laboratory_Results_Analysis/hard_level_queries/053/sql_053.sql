WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
required_labs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%creatinine%'
     OR label LIKE '%potassium%'
     OR label LIKE '%platelet%'
     OR label LIKE '%hemoglobin%'
     OR label LIKE '%white blood%'
     OR label LIKE '%whole blood potassium%'
),
lab_events_72h AS (
  SELECT
    le.hadm_id,
    le.subject_id,
    le.itemid,
    le.flag,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN patient_admissions pa
    ON le.hadm_id = pa.hadm_id
  INNER JOIN required_labs rl
    ON le.itemid = rl.itemid
  WHERE le.charttime BETWEEN pa.admittime
    AND TIMESTAMP_ADD(pa.admittime, INTERVAL 72 HOUR)
),
critical_lab_events AS (
  SELECT *
  FROM lab_events_72h
  WHERE flag = 'critical'
),
instability_score_per_admission AS (
  SELECT
    hadm_id,
    COUNT(*) AS instability_score
  FROM critical_lab_events
  GROUP BY hadm_id
),
all_admissions_with_score AS (
  SELECT
    pa.*,
    COALESCE(isp.instability_score, 0) AS instability_score
  FROM patient_admissions pa
  LEFT JOIN instability_score_per_admission isp
    ON pa.hadm_id = isp.hadm_id
),
percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS percentile_90
  FROM all_admissions_with_score
),
top_tier_admissions AS (
  SELECT *
  FROM all_admissions_with_score
  WHERE instability_score > (SELECT percentile_90 FROM percentile_90)
),
top_tier_metrics AS (
  SELECT
    AVG(hospital_expire_flag) AS mortality_top_tier,
    AVG(DATEDIFF(CAST(dischtime AS DATE), CAST(admittime AS DATE))) AS avg_los_top_tier
  FROM top_tier_admissions
),
top_tier_lab_events AS (
  SELECT
    rl.label AS lab_name,
    COUNT(*) AS total_events_top,
    SUM(CASE WHEN le.flag = 'critical' THEN 1 ELSE 0 END) AS critical_events_top
  FROM top_tier_admissions tta
  INNER JOIN lab_events_72h le
    ON tta.hadm_id = le.hadm_id
  INNER JOIN required_labs rl
    ON le.itemid = rl.itemid
  GROUP BY lab_name
),
all_lab_events AS (
  SELECT
    rl.label AS lab_name,
    COUNT(*) AS total_events_all,
    SUM(CASE WHEN le.flag = 'critical' THEN 1 ELSE 0 END) AS critical_events_all
  FROM all_admissions_with_score aas
  INNER JOIN lab_events_72h le
    ON aas.hadm_id = le.hadm_id
  INNER JOIN required_labs rl
    ON le.itemid = rl.itemid
  GROUP BY lab_name
),
lab_critical_rates AS (
  SELECT
    top.lab_name,
    critical_events_top * 1.0 / NULLIF(total_events_top, 0) AS critical_rate_top_tier,
    critical_events_all * 1.0 / NULLIF(total_events_all, 0) AS critical_rate_all
  FROM top_tier_lab_events top
  INNER JOIN all_lab_events `all`  -- Escaped reserved keyword
    ON top.lab_name = `all`.lab_name  -- Consistent reference
)
SELECT
  '90th_percentile' AS metric_name,
  percentile_90 AS value,
  NULL AS mortality,
  NULL AS avg_los,
  NULL AS lab_name,
  NULL AS critical_rate_top_tier,
  NULL AS critical_rate_all
FROM percentile_90
UNION ALL
SELECT
  'mortality_top_tier',
  mortality_top_tier,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM top_tier_metrics
UNION ALL
SELECT
  'avg_los_top_tier',
  avg_los_top_tier,
  NULL,
  NULL,
  NULL,
  NULL,
  NULL
FROM top_tier_metrics
UNION ALL
SELECT
  NULL,
  NULL,
  NULL,
  NULL,
  lab_name,
  critical_rate_top_tier,
  critical_rate_all
FROM lab_critical_rates;