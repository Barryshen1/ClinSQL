WITH ischemic_stroke_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND dd.icd_code = 'I63'
    AND dd.icd_version = 10
),

lab_instability_scores AS (
  SELECT
    lsp.hadm_id,
    lsp.admittime,
    COUNT(DISTINCT CASE WHEN l.flag = 'abnormal' THEN l.itemid END) AS instability_score
  FROM
    ischemic_stroke_patients lsp
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
  ON
    lsp.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN lsp.admittime AND DATETIME_ADD(lsp.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL
  GROUP BY
    lsp.hadm_id, lsp.admittime
),

instability_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS percentile_75
  FROM
    lab_instability_scores
),

high_instability_stroke AS (
  SELECT
    lis.*,
    isp.los_hours,
    isp.hospital_expire_flag
  FROM
    lab_instability_scores lis
  JOIN
    ischemic_stroke_patients isp
  ON
    lis.hadm_id = isp.hadm_id
  CROSS JOIN
    instability_percentile ip
  WHERE
    lis.instability_score >= ip.percentile_75
),

controls AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS hospital_expire_flag,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id AND dd.icd_code = 'I63' AND dd.icd_version = 10
    )
),

control_critical_labs AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS has_critical_lab
  FROM
    controls c
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
  ON
    c.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.hadm_id
),

stroke_critical_labs AS (
  SELECT
    his.hadm_id,
    MAX(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS has_critical_lab
  FROM
    high_instability_stroke his
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents l
  ON
    his.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN his.admittime AND DATETIME_ADD(his.admittime, INTERVAL 72 HOUR)
  GROUP BY
    his.hadm_id
)

SELECT
  '75th Percentile Instability Score' AS metric,
  ip.percentile_75 AS value,
  NULL AS group_type
FROM
  instability_percentile ip

UNION ALL

SELECT
  'Avg LOS (High Instability Stroke)' AS metric,
  AVG(his.los_hours) AS value,
  'High Instability Stroke' AS group_type
FROM
  high_instability_stroke his

UNION ALL

SELECT
  'Mortality Rate (High Instability Stroke)' AS metric,
  AVG(CAST(his.hospital_expire_flag AS FLOAT64)) AS value,
  'High Instability Stroke' AS group_type
FROM
  high_instability_stroke his

UNION ALL

SELECT
  'Critical Lab Rate (High Instability Stroke)' AS metric,
  AVG(CAST(scl.has_critical_lab AS FLOAT64)) AS value,
  'High Instability Stroke' AS group_type
FROM
  stroke_critical_labs scl
JOIN
  high_instability_stroke his
ON
  scl.hadm_id = his.hadm_id

UNION ALL

SELECT
  'Avg LOS (Controls)' AS metric,
  AVG(c.los_hours) AS value,
  'Controls' AS group_type
FROM
  controls c

UNION ALL

SELECT
  'Mortality Rate (Controls)' AS metric,
  AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS value,
  'Controls' AS group_type
FROM
  controls c

UNION ALL

SELECT
  'Critical Lab Rate (Controls)' AS metric,
  AVG(CAST(ccl.has_critical_lab AS FLOAT64)) AS value,
  'Controls' AS group_type
FROM
  control_critical_labs ccl
JOIN
  controls c
ON
  ccl.hadm_id = c.hadm_id
ORDER BY
  metric, group_type;