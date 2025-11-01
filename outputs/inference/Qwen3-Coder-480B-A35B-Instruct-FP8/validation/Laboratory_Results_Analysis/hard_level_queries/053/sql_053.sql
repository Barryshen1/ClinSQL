WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

lab_items_of_interest AS (
  SELECT
    itemid,
    LOWER(label) AS label
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) IN (
      'creatinine',
      'potassium',
      'platelets',
      'hemoglobin',
      'potassium, whole blood',
      'wbc'
    )
),

labevents_72h AS (
  SELECT
    l.hadm_id,
    l.itemid,
    l.valuenum,
    l.flag,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    cohort c
  ON
    l.hadm_id = c.hadm_id
  JOIN
    lab_items_of_interest li
  ON
    l.itemid = li.itemid
  WHERE
    l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.valuenum IS NOT NULL
),

abnormal_labs AS (
  SELECT
    hadm_id,
    itemid,
    CASE
      WHEN flag = 'abnormal' THEN 1
      WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    labevents_72h
),

instability_scores AS (
  SELECT
    hadm_id,
    SUM(is_abnormal) AS instability_score
  FROM
    abnormal_labs
  GROUP BY
    hadm_id
),

percentile_90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM
    instability_scores
),

top_tier AS (
  SELECT
    i.hadm_id
  FROM
    instability_scores i
  CROSS JOIN
    percentile_90 p
  WHERE
    i.instability_score >= p.p90_score
),

top_tier_summary AS (
  SELECT
    AVG(c.los) AS avg_los,
    AVG(c.hospital_expire_flag) AS mortality_rate
  FROM
    top_tier t
  JOIN
    cohort c
  ON
    t.hadm_id = c.hadm_id
),

lab_critical_rates_top AS (
  SELECT
    li.label,
    AVG(a.is_abnormal) AS critical_rate
  FROM
    abnormal_labs a
  JOIN
    top_tier t
  ON
    a.hadm_id = t.hadm_id
  JOIN
    lab_items_of_interest li
  ON
    a.itemid = li.itemid
  GROUP BY
    li.label
),

lab_critical_rates_all AS (
  SELECT
    li.label,
    AVG(a.is_abnormal) AS critical_rate
  FROM
    abnormal_labs a
  JOIN
    lab_items_of_interest li
  ON
    a.itemid = li.itemid
  GROUP BY
    li.label
)

SELECT
  (SELECT p90_score FROM percentile_90) AS p90_instability_score,
  t.avg_los,
  t.mortality_rate,
  c.label,
  c.critical_rate AS top_tier_critical_rate,
  a.critical_rate AS all_patients_critical_rate
FROM
  top_tier_summary t
CROSS JOIN
  lab_critical_rates_top c
JOIN
  lab_critical_rates_all a
ON
  c.label = a.label
ORDER BY
  c.label;