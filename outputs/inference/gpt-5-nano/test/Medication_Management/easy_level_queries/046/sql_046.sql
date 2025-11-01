WITH filtered_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON a.subject_id = pat.subject_id
  WHERE (
        LOWER(p.drug) LIKE '%spironolactone%'
        OR LOWER(p.drug) LIKE '%eplerenone%'
      )
    AND pat.gender = 'Male'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.starttime >= a.admittime
    AND p.starttime <= a.dischtime
),
durations AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0 AS duration_days
  FROM filtered_prescriptions
)
SELECT
  MEDIAN(duration_days) AS median_duration_days
FROM durations;