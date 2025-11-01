WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
),
spiro_eple_prescriptions AS (
  SELECT
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    pa.subject_id = pr.subject_id
    AND pa.hadm_id = pr.hadm_id
  WHERE
    pr.stoptime IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%spironolactone%'
      OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM
  spiro_eple_prescriptions;