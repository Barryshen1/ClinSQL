WITH female_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 42 AND 52
),
amio_prescriptions AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    female_admissions fa
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON fa.subject_id = pr.subject_id
     AND fa.hadm_id    = pr.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime >= fa.admittime
    AND pr.stoptime  <= fa.dischtime
    AND pr.stoptime  > pr.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS duration_25th_percentile_days
FROM
  amio_prescriptions;