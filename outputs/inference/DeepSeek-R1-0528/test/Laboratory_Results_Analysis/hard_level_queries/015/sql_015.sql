WITH stroke_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491', '436'))
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),
stroke_lab_abnormalities AS (
  SELECT
    sc.hadm_id,
    COUNT(le.labevent_id) AS instability_score
  FROM stroke_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN sc.admittime AND DATETIME_ADD(sc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY sc.hadm_id
),
p75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM stroke_lab_abnormalities
),
high_instability_stroke AS (
  SELECT
    sc.*,
    la.instability_score
  FROM stroke_cohort sc
  INNER JOIN stroke_lab_abnormalities la
    ON sc.hadm_id = la.hadm_id
  WHERE la.instability_score >= (SELECT p75_score FROM p75)
),
control_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        (d.icd_version = 9 AND d.icd_code IN ('43301', '43311', '43321', '43331', '43381', '43391', '43401', '43411', '43491', '436'))
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I63%')
    )
),
control_lab_abnormalities AS (
  SELECT
    cc.hadm_id,
    COUNT(le.labevent_id) AS instability_score
  FROM control_cohort cc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN cc.admittime AND DATETIME_ADD(cc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY cc.hadm_id
)
SELECT
  metric,
  value,
  group_label
FROM (
  -- 75th percentile of instability score
  SELECT
    'p75_instability_score' AS metric,
    CAST(p75_score AS STRING) AS value,
    CAST(NULL AS STRING) AS group_label
  FROM p75
  UNION ALL
  -- High-instability group: Count
  SELECT
    'high_instability_n' AS metric,
    CAST(COUNT(*) AS STRING) AS value,
    CAST(NULL AS STRING) AS group_label
  FROM high_instability_stroke
  UNION ALL
  -- High-instability group: Avg LOS (days)
  SELECT
    'high_instability_avg_los' AS metric,
    CAST(AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS STRING) AS value,
    CAST(NULL AS STRING) AS group_label
  FROM high_instability_stroke
  UNION ALL
  -- High-instability group: Mortality rate
  SELECT
    'high_instability_mortality_rate' AS metric,
    CAST(AVG(hospital_expire_flag) AS STRING) AS value,
    CAST(NULL AS STRING) AS group_label
  FROM high_instability_stroke
  UNION ALL
  -- Critical lab rate comparison (high-instability vs. control)
  SELECT
    'critical_lab_rate' AS metric,
    CAST(AVG(instability_score) AS STRING) AS value,
    group_label
  FROM (
    SELECT
      'High-instability stroke' AS group_label,
      instability_score
    FROM high_instability_stroke
    UNION ALL
    SELECT
      'Control' AS group_label,
      COALESCE(instability_score, 0) AS instability_score
    FROM control_cohort cc
    LEFT JOIN control_lab_abnormalities cla
      ON cc.hadm_id = cla.hadm_id
  ) t
  GROUP BY group_label
);