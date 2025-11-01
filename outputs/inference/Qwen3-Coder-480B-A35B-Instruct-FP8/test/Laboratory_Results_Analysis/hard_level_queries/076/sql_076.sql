WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

lab_scores AS (
  SELECT
    c.hadm_id,
    STDDEV_SAMP(le.valuenum) AS lab_instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    c.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    le.itemid = d.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND DATETIME_DIFF(le.charttime, c.admittime, HOUR) BETWEEN 0 AND 72
    AND LOWER(d.label) IN (
      'wbc', 'sodium', 'potassium', 'bicarbonate', 'chloride',
      'creatinine', 'glucose', 'hemoglobin', 'platelet count'
    )
  GROUP BY
    c.hadm_id
),

score_percentiles AS (
  SELECT
    *,
    PERCENTILE_CONT(lab_instability_score, 0.95) OVER() AS p95_score
  FROM
    lab_scores
),

high_instability AS (
  SELECT
    c.*,
    s.lab_instability_score
  FROM
    cohort c
  JOIN
    score_percentiles s
  ON
    c.hadm_id = s.hadm_id
  WHERE
    s.lab_instability_score >= s.p95_score
),

critical_labs AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE
    le.flag = 'abnormal'
  GROUP BY
    le.hadm_id
),

high_instability_with_labs AS (
  SELECT
    h.*,
    COALESCE(cl.critical_lab_count, 0) AS critical_lab_count
  FROM
    high_instability h
  LEFT JOIN
    critical_labs cl
  ON
    h.hadm_id = cl.hadm_id
),

general_cohort_with_labs AS (
  SELECT
    c.*,
    COALESCE(cl.critical_lab_count, 0) AS critical_lab_count
  FROM
    cohort c
  LEFT JOIN
    critical_labs cl
  ON
    c.hadm_id = cl.hadm_id
)

SELECT
  -- High instability group stats
  AVG(h.los_days) AS mean_los_days,
  AVG(h.hospital_expire_flag) AS in_hospital_mortality,
  AVG(h.critical_lab_count) AS avg_critical_labs_per_patient,

  -- General cohort stats
  (SELECT AVG(los_days) FROM general_cohort_with_labs) AS general_mean_los,
  (SELECT AVG(hospital_expire_flag) FROM general_cohort_with_labs) AS general_mortality,
  (SELECT AVG(critical_lab_count) FROM general_cohort_with_labs) AS general_avg_critical_labs
FROM
  high_instability_with_labs h;