WITH cohort AS (
  SELECT
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
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND dd.icd_code LIKE 'A41%' -- Sepsis ICD-10 codes
    AND d.icd_version = 10
),

critical_labs AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  JOIN
    cohort c
  ON
    l.hadm_id = c.hadm_id
  WHERE
    l.charttime IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (
      (d.label LIKE '%lactate%' AND l.valuenum > 2.0) OR
      (d.label LIKE '%creatinine%' AND l.valuenum > 1.2) OR
      (d.label LIKE '%bilirubin%' AND l.valuenum > 1.2) OR
      (l.flag = 'abnormal')
    )
  GROUP BY
    l.hadm_id
),

instability_scores AS (
  SELECT
    c.hadm_id,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(cl.critical_lab_count, 0) AS instability_score
  FROM
    cohort c
  LEFT JOIN
    critical_labs cl
  ON
    c.hadm_id = cl.hadm_id
)

SELECT
  COUNT(*) AS cohort_size,
  AVG(instability_score) AS mean_instability_score,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS percentile_25_instability_score,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  instability_scores;