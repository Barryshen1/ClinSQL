WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),
target_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN cohort c
      ON pr.subject_id = c.subject_id
      AND pr.hadm_id = c.hadm_id
  WHERE
    LOWER(pr.drug) IN ('spironolactone', 'eplerenone')
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
single_prescription_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS num_prescriptions
  FROM
    target_prescriptions
  GROUP BY
    subject_id,
    hadm_id
  HAVING
    COUNT(*) = 1
),
single_prescription_durations AS (
  SELECT
    tp.subject_id,
    tp.hadm_id,
    tp.drug,
    DATE_DIFF(DATE(tp.stoptime), DATE(tp.starttime), DAY) AS duration_days
  FROM
    target_prescriptions tp
    JOIN single_prescription_admissions spa
      ON tp.subject_id = spa.subject_id
      AND tp.hadm_id = spa.hadm_id
  WHERE
    DATE(tp.stoptime) >= DATE(tp.starttime)
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM
  single_prescription_durations
;