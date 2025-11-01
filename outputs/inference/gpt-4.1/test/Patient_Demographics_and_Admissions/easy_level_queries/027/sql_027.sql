WITH first_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, first_admission_per_patient AS (
  SELECT
    subject_id,
    los_days
  FROM (
    SELECT
      subject_id,
      los_days,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM first_admissions
  )
  WHERE rn = 1
)
SELECT
  quantiles[OFFSET(2)] - quantiles[OFFSET(0)] AS iqr_los_days,
  quantiles[OFFSET(0)] AS q1,
  quantiles[OFFSET(2)] AS q3
FROM (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM first_admission_per_patient
);