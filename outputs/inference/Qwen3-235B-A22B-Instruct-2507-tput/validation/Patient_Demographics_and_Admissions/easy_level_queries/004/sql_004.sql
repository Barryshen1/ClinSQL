WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
),
aged_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    gender,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM
    first_admissions
  WHERE
    rn = 1
    AND gender = 'F'
    AND anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 70 AND 80
)
SELECT
  STDDEV(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS los_std_days
FROM
  aged_admissions
WHERE
  dischtime IS NOT NULL;