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
    AND p.anchor_age BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

lab_scores AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS instability_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    c.hadm_id = l.hadm_id
  WHERE
    l.charttime >= c.admittime
    AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (l.flag = 'abnormal' OR l.flag = 'high' OR l.flag = 'low')
  GROUP BY
    c.hadm_id
),

score_percentiles AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_score
  FROM
    lab_scores
),

high_risk_admissions AS (
  SELECT
    ls.hadm_id,
    c.hospital_expire_flag,
    c.los_days
  FROM
    lab_scores ls
  CROSS JOIN
    score_percentiles sp
  JOIN
    cohort c
  ON
    ls.hadm_id = c.hadm_id
  WHERE
    ls.instability_score >= sp.p95_score
),

high_risk_metrics AS (
  SELECT
    'High Instability' AS group_name,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN l.flag IN ('abnormal', 'high', 'low') THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM
    high_risk_admissions hra
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    hra.hadm_id = l.hadm_id
  WHERE
    l.charttime >= (
      SELECT admittime FROM cohort c WHERE c.hadm_id = l.hadm_id
    )
    AND l.charttime <= DATETIME_ADD(
      (SELECT admittime FROM cohort c WHERE c.hadm_id = l.hadm_id), INTERVAL 48 HOUR
    )
),

control_cohort AS (
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
    AND p.anchor_age BETWEEN 54 AND 64
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

control_metrics AS (
  SELECT
    'Control' AS group_name,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_days) AS mean_los,
    AVG(CASE WHEN l.flag IN ('abnormal', 'high', 'low') THEN 1 ELSE 0 END) AS critical_lab_rate
  FROM
    control_cohort cc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON
    cc.hadm_id = l.hadm_id
  WHERE
    l.charttime >= cc.admittime
    AND l.charttime <= DATETIME_ADD(cc.admittime, INTERVAL 48 HOUR)
)

SELECT * FROM high_risk_metrics
UNION ALL
SELECT * FROM control_metrics;