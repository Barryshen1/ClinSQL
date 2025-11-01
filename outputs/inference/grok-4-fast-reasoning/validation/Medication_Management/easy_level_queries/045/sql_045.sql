WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 57 AND 67
),
durations AS (
  SELECT
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  INNER JOIN cohort c
    ON pres.hadm_id = c.hadm_id
  WHERE pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime
    AND (
      LOWER(pres.drug) LIKE '%aspirin%'
      OR LOWER(pres.drug) LIKE '%clopidogrel%'
      OR LOWER(pres.drug) LIKE '%prasugrel%'
      OR LOWER(pres.drug) LIKE '%ticagrelor%'
    )
    AND TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) > 0
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS Q1_days,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS Q3_days,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS IQR_days
FROM durations;