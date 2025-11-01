WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
),
filtered_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    patient_admissions
  WHERE
    age_at_admission BETWEEN 43 AND 53
),
warfarin_prescriptions AS (
  SELECT
    f.hadm_id,
    p.starttime,
    p.stoptime,
    (UNIX_SECONDS(CAST(p.stoptime AS TIMESTAMP)) - UNIX_SECONDS(CAST(p.starttime AS TIMESTAMP))) / (24 * 60 * 60) AS duration_days
  FROM
    filtered_admissions f
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON f.hadm_id = p.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%warfarin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime >= p.starttime
)
SELECT
  AVG(duration_days) AS avg_warfarin_duration_days
FROM
  warfarin_prescriptions;