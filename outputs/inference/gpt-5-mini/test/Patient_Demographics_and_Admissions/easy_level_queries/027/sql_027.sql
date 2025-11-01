WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime ASC, a.hadm_id ASC) = 1
),

counts AS (
  SELECT COUNT(*) AS n_patients
  FROM first_admissions
),

stats AS (
  SELECT APPROX_QUANTILES(los_days, 4) AS q
  FROM first_admissions
)

SELECT
  c.n_patients,
  s.q[OFFSET(1)] AS q1_days,        -- 25th percentile
  s.q[OFFSET(3)] AS q3_days,        -- 75th percentile
  s.q[OFFSET(3)] - s.q[OFFSET(1)] AS iqr_days
FROM counts c
CROSS JOIN stats s;