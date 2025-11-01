WITH
-- 1. Base male admissions age 49–59
adm_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
),

-- 2. Identify ischemic-stroke admissions
stroke_adm AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    dd.long_title LIKE '%ischemic stroke%'
),

-- 3. Compute 72h lab counts per hadm_id for any input set
lab_counts AS (
  SELECT
    b.hadm_id,
    COUNT(*) AS total_labs_72h,
    SUM(CASE
      WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN 1
      ELSE 0
    END) AS crit_labs_72h
  FROM
    adm_base b
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON b.hadm_id = le.hadm_id
      AND le.charttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
  GROUP BY
    b.hadm_id
),

-- 4. Stroke cohort with their instability scores
stroke_scores AS (
  SELECT
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    b.anchor_age,
    lc.total_labs_72h,
    lc.crit_labs_72h AS instability_score
  FROM
    adm_base b
    JOIN stroke_adm s ON b.hadm_id = s.hadm_id
    LEFT JOIN lab_counts lc ON b.hadm_id = lc.hadm_id
),

-- 5. Compute 75th percentile instability score among strokes
stroke_p75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM
    stroke_scores
),

-- 6. Label high-instability strokes
stroke_high AS (
  SELECT
    ss.*
  FROM
    stroke_scores ss,
    stroke_p75 p
  WHERE
    ss.instability_score >= p.p75_score
),

-- 7. Define controls (male age 49–59, no ischemic stroke)
controls AS (
  SELECT
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    b.anchor_age
  FROM
    adm_base b
  LEFT JOIN stroke_adm s ON b.hadm_id = s.hadm_id
  WHERE
    s.hadm_id IS NULL
),

-- 8. Compute control lab counts (reuse lab_counts)
control_scores AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age,
    lc.total_labs_72h,
    lc.crit_labs_72h AS instability_score
  FROM
    controls c
    LEFT JOIN lab_counts lc ON c.hadm_id = lc.hadm_id
),

-- 9. Summarize metrics for stroke_high and controls
summary AS (
  SELECT
    'High-Instability Stroke' AS group_label,
    COUNT(*) AS n_patients,
    AVG(DATE_DIFF(DISCHTIME, ADMITTIME, DAY)) AS avg_los_days,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate,
    AVG(instability_score) AS avg_crit_labs_72h
  FROM
    stroke_high

  UNION ALL

  SELECT
    'Age-Matched Controls' AS group_label,
    COUNT(*) AS n_patients,
    AVG(DATE_DIFF(DISCHTIME, ADMITTIME, DAY)) AS avg_los_days,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) AS mortality_rate,
    AVG(instability_score) AS avg_crit_labs_72h
  FROM
    control_scores
)

SELECT * FROM summary;