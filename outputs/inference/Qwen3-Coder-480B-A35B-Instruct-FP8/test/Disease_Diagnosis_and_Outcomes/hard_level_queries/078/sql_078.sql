WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE WHEN a.deathtime IS NOT NULL THEN DATETIME_DIFF(a.deathtime, a.admittime, HOUR) ELSE NULL END AS survival_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
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
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),

aki AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN valuenum > 1.5 THEN 1 ELSE 0 END) AS aki_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) LIKE '%creatinine%'
    AND valuenum IS NOT NULL
  GROUP BY
    hadm_id
),

ards AS (
  SELECT
    ce.hadm_id,
    MAX(CASE WHEN ce.valuenum < 300 THEN 1 ELSE 0 END) AS ards_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%pao2/fio2%'
    AND ce.valuenum IS NOT NULL
  GROUP BY
    ce.hadm_id
),

labs AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(dl.label) LIKE '%creatinine%' THEN le.valuenum END) AS creatinine_max,
    MAX(CASE WHEN LOWER(dl.label) LIKE '%lactate%' THEN le.valuenum END) AS lactate_max,
    MAX(CASE WHEN LOWER(dl.label) LIKE '%wbc%' THEN le.valuenum END) AS wbc_max
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) IN ('creatinine', 'lactate', 'wbc')
    AND le.valuenum IS NOT NULL
  GROUP BY
    hadm_id
),

scores AS (
  SELECT
    c.*,
    COALESCE(l.creatinine_max, 0) AS creatinine_max,
    COALESCE(l.lactate_max, 0) AS lactinine_max,
    COALESCE(l.wbc_max, 0) AS wbc_max,
    CASE
      WHEN c.anchor_age BETWEEN 59 AND 64 THEN 1
      WHEN c.anchor_age BETWEEN 65 AND 69 THEN 2
      ELSE 0
    END AS age_score,
    CASE
      WHEN l.creatinine_max > 1.5 THEN 1
      ELSE 0
    END AS creatinine_score,
    CASE
      WHEN l.lactate_max > 2 THEN 1
      ELSE 0
    END AS lactate_score,
    CASE
      WHEN l.wbc_max < 4 OR l.wbc_max > 12 THEN 1
      ELSE 0
    END AS wbc_score
  FROM
    cohort c
  LEFT JOIN
    labs l
  ON
    c.hadm_id = l.hadm_id
),

risk_scores AS (
  SELECT
    *,
    age_score + creatinine_score + lactate_score + wbc_score AS composite_score
  FROM
    scores
)

SELECT
  COUNT(*) AS total_patients,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(COALESCE(aki.aki_flag, 0)) AS aki_rate,
  AVG(COALESCE(ards.ards_flag, 0)) AS ards_rate,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(0)] AS min_score,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS p25_score,
  APPROX_QUANTILES(composite_score, 2)[OFFSET(1)] AS median_score,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS p75_score,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(90)] AS p90_score,
  APPROX_QUANTILES(composite_score, 100)[OFFSET(100)] AS max_score,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN survival_hours END) AS median_survival_hours
FROM
  risk_scores
LEFT JOIN
  aki
USING
  (hadm_id)
LEFT JOIN
  ards
USING
  (hadm_id);