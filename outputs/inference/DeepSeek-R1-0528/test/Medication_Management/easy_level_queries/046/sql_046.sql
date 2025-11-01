WITH eligible_prescriptions AS (
  SELECT
    DATETIME_DIFF(rx.stoptime, rx.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON adm.hadm_id = rx.hadm_id
    AND adm.subject_id = rx.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 90 AND 100
    AND (LOWER(rx.drug) LIKE '%spironolactone%' OR LOWER(rx.drug) LIKE '%eplerenone%')
    AND rx.stoptime IS NOT NULL
    AND rx.stoptime > rx.starttime
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM
  eligible_prescriptions;