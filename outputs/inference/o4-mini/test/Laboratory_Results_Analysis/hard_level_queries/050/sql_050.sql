WITH base_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),
ards_admissions AS (
  SELECT DISTINCT
    di.subject_id,
    di.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ards%'
),
lab_instability AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    COUNT(*) AS instability_score
  FROM
    base_patients bp
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON bp.subject_id = le.subject_id
      AND bp.hadm_id = le.hadm_id
      AND le.valuenum IS NOT NULL
      AND le.ref_range_lower IS NOT NULL
      AND le.ref_range_upper IS NOT NULL
      AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
      AND le.charttime BETWEEN bp.admittime
        AND TIMESTAMP_ADD(bp.admittime, INTERVAL 72 HOUR)
  GROUP BY
    bp.subject_id,
    bp.hadm_id
),
all_scores AS (
  SELECT
    bp.subject_id,
    bp.hadm_id,
    IFNULL(li.instability_score, 0) AS instability_score,
    CASE WHEN ar.hadm_id IS NOT NULL THEN TRUE ELSE FALSE END AS is_ards,
    bp.admittime,
    bp.dischtime,
    bp.hospital_expire_flag
  FROM
    base_patients bp
    LEFT JOIN lab_instability li
      ON bp.subject_id = li.subject_id
      AND bp.hadm_id = li.hadm_id
    LEFT JOIN ards_admissions ar
      ON bp.subject_id = ar.subject_id
      AND bp.hadm_id = ar.hadm_id
),
ards_scores AS (
  SELECT * FROM all_scores WHERE is_ards = TRUE
),
non_ards_scores AS (
  SELECT * FROM all_scores WHERE is_ards = FALSE
),
threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS thr
  FROM ards_scores
),
ards_high_risk AS (
  SELECT
    *
  FROM
    ards_scores s
    CROSS JOIN threshold t
  WHERE
    s.instability_score >= t.thr
)

SELECT
  t.thr AS threshold_75_pct_instability_score,
  -- ARDS ≥ threshold outcomes
  ROUND(
    (SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) FROM ards_high_risk)
    , 3
  ) AS ards_mortality_rate,
  ROUND(
    (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) FROM ards_high_risk)
    , 2
  ) AS ards_mean_los_days,
  ROUND(
    (SELECT AVG(instability_score) FROM ards_high_risk)
    , 2
  ) AS ards_mean_critical_events_per_patient,
  -- Non‐ARDS average critical events per patient
  ROUND(
    (SELECT AVG(instability_score) FROM non_ards_scores)
    , 2
  ) AS non_ards_mean_critical_events_per_patient
FROM
  threshold t;