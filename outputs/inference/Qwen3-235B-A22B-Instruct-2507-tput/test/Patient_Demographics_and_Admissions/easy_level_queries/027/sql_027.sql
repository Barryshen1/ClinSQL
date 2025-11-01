WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate length of stay in days (fractional)
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
first_admissions AS (
  SELECT
    subject_id,
    MIN(admittime) AS first_admittime
  FROM
    patient_ages
  WHERE
    age_at_admission BETWEEN 77 AND 87
  GROUP BY
    subject_id
),
first_admission_los AS (
  SELECT
    pa.los_days
  FROM
    patient_ages pa
  INNER JOIN
    first_admissions fa
  ON
    pa.subject_id = fa.subject_id AND pa.admittime = fa.first_admittime
)
SELECT
  APPROX_QUANTILES(los_days, 1000)[OFFSET(750)] - APPROX_QUANTILES(los_days, 1000)[OFFSET(250)] AS iqr_los_days
FROM
  first_admission_los;