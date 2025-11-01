WITH cohort AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    a.hospital_expire_flag,
    MAX(CASE WHEN did.long_title LIKE '%hyperosmolar%' THEN 1 ELSE 0 END) AS hhs_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.hadm_id = a.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON a.hadm_id = dx.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON dx.icd_code = did.icd_code AND dx.icd_version = did.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
  GROUP BY
    p.subject_id, icu.stay_id, icu.intime, icu.outtime, icu.los, a.hospital_expire_flag
),

controls AS (
  SELECT *
  FROM cohort
  WHERE hhs_flag = 0
),

hhs_patients AS (
  SELECT *
  FROM cohort
  WHERE hhs_flag = 1
),

matched_controls AS (
  SELECT
    c.*,
    'Control' AS group_label
  FROM controls c
  WHERE c.subject_id NOT IN (SELECT subject_id FROM hhs_patients)
),

all_patients AS (
  SELECT *, 'HHS' AS group_label FROM hhs_patients
  UNION ALL
  SELECT * FROM matched_controls
),

vitals_first48 AS (
  SELECT
    ce.stay_id,
    di.label,
    ce.valuenum,
    ce.charttime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    all_patients ap
    ON ce.stay_id = ap.stay_id
  WHERE
    di.label IN ('Heart Rate', 'Respiratory Rate', 'Temperature Fahrenheit', 'Arterial Blood Pressure systolic', 'GCS Total')
    AND ce.charttime >= ap.intime
    AND ce.charttime <= DATETIME_ADD(ap.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),

vital_stats AS (
  SELECT
    stay_id,
    AVG(CASE WHEN label = 'Heart Rate' THEN valuenum END) AS hr_mean,
    AVG(CASE WHEN label = 'Respiratory Rate' THEN valuenum END) AS rr_mean,
    AVG(CASE WHEN label = 'Temperature Fahrenheit' THEN valuenum END) AS temp_mean,
    AVG(CASE WHEN label = 'Arterial Blood Pressure systolic' THEN valuenum END) AS sbp_mean,
    AVG(CASE WHEN label = 'GCS Total' THEN valuenum END) AS gcs_mean,

    AVG(CASE
      WHEN label = 'Heart Rate' AND (valuenum < 60 OR valuenum > 100) THEN 1
      WHEN label = 'Respiratory Rate' AND (valuenum < 12 OR valuenum > 20) THEN 1
      WHEN label = 'Temperature Fahrenheit' AND (valuenum < 95 OR valuenum > 100.4) THEN 1
      WHEN label = 'Arterial Blood Pressure systolic' AND (valuenum < 90 OR valuenum > 140) THEN 1
      WHEN label = 'GCS Total' AND valuenum < 15 THEN 1
      ELSE 0
    END) AS abnormal_vital_burden
  FROM vitals_first48
  GROUP BY stay_id
),

instability_score AS (
  SELECT
    vs.stay_id,
    ap.group_label,
    ap.icu_los,
    ap.hospital_expire_flag,

    -- Composite instability score (example weights)
    COALESCE(ABS(vs.hr_mean - 80) / 20, 0) +
    COALESCE(ABS(vs.sbp_mean - 120) / 20, 0) +
    COALESCE(ABS(vs.rr_mean - 16) / 4, 0) +
    COALESCE(ABS(vs.temp_mean - 98.6) / 2, 0) +
    COALESCE((15 - vs.gcs_mean), 0) AS instability_score,

    vs.abnormal_vital_burden
  FROM vital_stats vs
  JOIN all_patients ap
    ON vs.stay_id = ap.stay_id
)

SELECT
  is.group_label,
  APPROX_QUANTILES(is.instability_score, 4)[OFFSET(1)] AS instability_score_p25,
  APPROX_QUANTILES(is.instability_score, 2)[OFFSET(1)] AS instability_score_median,
  APPROX_QUANTILES(is.instability_score, 4)[OFFSET(3)] AS instability_score_p75,

  APPROX_QUANTILES(is.abnormal_vital_burden, 4)[OFFSET(1)] AS abnormal_vital_burden_p25,
  APPROX_QUANTILES(is.abnormal_vital_burden, 2)[OFFSET(1)] AS abnormal_vital_burden_median,
  APPROX_QUANTILES(is.abnormal_vital_burden, 4)[OFFSET(3)] AS abnormal_vital_burden_p75,

  APPROX_QUANTILES(is.icu_los, 4)[OFFSET(1)] AS icu_los_p25,
  APPROX_QUANTILES(is.icu_los, 2)[OFFSET(1)] AS icu_los_median,
  APPROX_QUANTILES(is.icu_los, 4)[OFFSET(3)] AS icu_los_p75,

  AVG(CAST(is.hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM instability_score is
GROUP BY is.group_label
ORDER BY is.group_label;