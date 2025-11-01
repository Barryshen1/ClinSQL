WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 90 AND 100
),
thiazide_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
  INNER JOIN
    patient_admissions pa
  ON
    pr.subject_id = pa.subject_id
  WHERE
    LOWER(pr.drug) IN ('chlorthalidone', 'indapamide', 'metolazone')
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3
  FROM
    thiazide_prescriptions
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr_days
FROM
  thiazide_prescriptions;