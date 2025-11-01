WITH female_40_50 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),

ards_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
  FROM
    female_40_50 f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    f.subject_id = d.subject_id
    AND f.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'J80'
    AND d.icd_version = 10
),

lab_events_ards AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    ards_patients a
  ON
    l.subject_id = a.subject_id
    AND l.hadm_id = a.hadm_id
  WHERE
    l.charttime >= a.admittime
    AND l.charttime <= a.admittime + INTERVAL '72' HOUR
),

abnormal_lab_events AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL
        AND (valuenum < ref_range_lower OR valuenum > ref_range_upper)
      THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    lab_events_ards
),

score_ards AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_abnormal) AS lab_score
  FROM
    abnormal_lab_events
  GROUP BY
    subject_id, hadm_id
),

percentile_75 AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_score) AS threshold
  FROM
    score_ards
),

high_risk AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    s.lab_score
  FROM
    ards_patients a
  JOIN
    score_ards s
  ON
    a.subject_id = s.subject_id
    AND a.hadm_id = s.hadm_id
  JOIN
    percentile_75 p
  ON
    s.lab_score >= p.threshold
),

high_risk_stats AS (
  SELECT
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los) AS mean_los,
    AVG(lab_score) AS avg_lab_score_high
  FROM
    high_risk
),

non_ards_patients AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime
  FROM
    female_40_50 f
  LEFT JOIN
    ards_patients a
  ON
    f.subject_id = a.subject_id
    AND f.hadm_id = a.hadm_id
  WHERE
    a.subject_id IS NULL
),

lab_events_non_ards AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    non_ards_patients n
  ON
    l.subject_id = n.subject_id
    AND l.hadm_id = n.hadm_id
  WHERE
    l.charttime >= n.admittime
    AND l.charttime <= n.admittime + INTERVAL '72' HOUR
),

abnormal_lab_non_ards AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL
        AND (valuenum < ref_range_lower OR valuenum > ref_range_upper)
      THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    lab_events_non_ards
),

score_non_ards AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(is_abnormal) AS lab_score
  FROM
    abnormal_lab_non_ards
  GROUP BY
    subject_id, hadm_id
),

non_ards_avg AS (
  SELECT
    AVG(lab_score) AS avg_lab_score_non_ards
  FROM
    score_non_ards
)

SELECT
  h.mortality_rate,
  h.mean_los,
  h.avg_lab_score_high,
  n.avg_lab_score_non_ards
FROM
  high_risk_stats h
CROSS JOIN
  non_ards_avg n;