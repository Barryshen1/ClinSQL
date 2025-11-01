WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'transfer from another hospital'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
los_data AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('Home', 'Home Health Care') THEN 'home'
      WHEN discharge_location IN ('Skilled Nursing Facility', 'Long Term Care Hospital', 'Rehabilitation Facility') THEN 'facility'
      ELSE 'other'
    END AS outcome_group
  FROM
    filtered_admissions
)
SELECT
  outcome_group,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  (COUNT(CASE WHEN los <= 10 THEN 1 END) * 100.0) / COUNT(*) AS percent_le10
FROM
  los_data
GROUP BY
  outcome_group
ORDER BY
  outcome_group;