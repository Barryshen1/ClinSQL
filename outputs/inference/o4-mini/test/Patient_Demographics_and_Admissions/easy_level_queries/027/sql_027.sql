WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      dischtime,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
  ) a
  WHERE
    a.rn = 1
    AND a.dischtime IS NOT NULL
),
eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
)
SELECT
  quantiles[OFFSET(25)] AS los_q1_days,
  quantiles[OFFSET(75)] AS los_q3_days
FROM (
  SELECT
    APPROX_QUANTILES(f.los_days, 100) AS quantiles
  FROM
    first_admissions f
  JOIN
    eligible_patients e
  ON
    f.subject_id = e.subject_id
);