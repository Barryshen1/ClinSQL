WITH cohort_dvt AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND LOWER(di.long_title) LIKE '%deep vein thrombosis%'
),

lab_scores AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    l.itemid,
    l.valuenum,
    l.charttime,
    DATETIME_DIFF(l.charttime, c.admittime, HOUR) AS delta_hours
  FROM
    cohort_dvt c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATETIME_DIFF(l.charttime, c.admittime, HOUR) BETWEEN 0 AND 72
    AND LOWER(d.label) IN ('wbc', 'sodium', 'potassium', 'bicarbonate', 'creatinine', 'chloride', 'glucose', 'hematocrit', 'platelet count')
),

lab_stats AS (
  SELECT
    hadm_id,
    itemid,
    AVG(valuenum) AS mean_val,
    STDDEV(valuenum) AS stddev_val
  FROM
    lab_scores
  GROUP BY
    hadm_id, itemid
  HAVING
    AVG(valuenum) > 0
),

instability_scores AS (
  SELECT
    hadm_id,
    AVG(CASE WHEN mean_val > 0 THEN stddev_val / mean_val ELSE NULL END) AS instability_score
  FROM
    lab_stats
  GROUP BY
    hadm_id
),

percentile_95 AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_score
  FROM
    instability_scores
  LIMIT 1
),

high_instability_cohort AS (
  SELECT
    i.hadm_id,
    i.instability_score,
    c.hospital_expire_flag,
    c.los_days
  FROM
    instability_scores i
  JOIN
    cohort_dvt c
  ON
    i.hadm_id = c.hadm_id
  CROSS JOIN
    percentile_95 p
  WHERE
    i.instability_score >= p.p95_score
),

all_labs AS (
  SELECT
    l.hadm_id,
    l.itemid,
    l.flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE
    l.flag IN ('abnormal', 'critical')
),

critical_labs_high AS (
  SELECT
    COUNT(DISTINCT a.itemid) AS critical_count,
    COUNT(*) AS total_labs
  FROM
    high_instability_cohort h
  JOIN
    all_labs a
  ON
    h.hadm_id = a.hadm_id
),

critical_labs_all AS (
  SELECT
    COUNT(DISTINCT itemid) AS critical_count,
    COUNT(*) AS total_labs
  FROM
    all_labs
)

SELECT
  'High Instability Cohort (>=95th percentile)' AS cohort,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  (SELECT critical_count FROM critical_labs_high) / NULLIF((SELECT total_labs FROM critical_labs_high), 0) AS critical_lab_rate
FROM
  high_instability_cohort

UNION ALL

SELECT
  'All Inpatients' AS cohort,
  NULL AS patient_count,
  NULL AS mortality_rate,
  NULL AS mean_los_days,
  (SELECT critical_count FROM critical_labs_all) / NULLIF((SELECT total_labs FROM critical_labs_all), 0) AS critical_lab_rate;