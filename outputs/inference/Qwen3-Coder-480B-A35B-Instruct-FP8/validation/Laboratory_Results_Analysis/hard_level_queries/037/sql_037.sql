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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I61%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I62%')
    )
),

first_48h_labs AS (
  SELECT
    l.hadm_id,
    l.itemid,
    l.flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    cohort c
  ON
    l.hadm_id = c.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND l.flag = 'abnormal'
    AND l.itemid IN (
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) IN (
        'creatinine', 'white blood cell count', 'platelet count',
        'lactate', 'bicarbonate', 'potassium', 'sodium'
      )
    )
),

instability_score AS (
  SELECT
    hadm_id,
    COUNT(*) AS instability_score
  FROM
    first_48h_labs
  GROUP BY
    hadm_id
),

percentile_25 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS score_25th_percentile
  FROM
    instability_score
),

general_labs AS (
  SELECT
    l.hadm_id,
    l.flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    l.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND l.flag = 'abnormal'
    AND l.itemid IN (
      SELECT itemid
      FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE LOWER(label) IN (
        'creatinine', 'white blood cell count', 'platelet count',
        'lactate', 'bicarbonate', 'potassium', 'sodium'
      )
    )
),

general_abnormal_rate AS (
  SELECT
    COUNT(*) AS total_flagged_labs,
    COUNT(DISTINCT l.hadm_id) AS total_admissions
  FROM
    general_labs l
),

cohort_stats AS (
  SELECT
    AVG(c.los_days) AS mean_los,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    cohort c
)

SELECT
  p.score_25th_percentile,
  g.total_flagged_labs,
  g.total_admissions,
  ROUND(SAFE_DIVIDE(g.total_flagged_labs, g.total_admissions), 4) AS avg_critical_labs_per_admission,
  s.mean_los,
  s.mortality_rate
FROM
  percentile_25 p,
  general_abnormal_rate g,
  cohort_stats s;