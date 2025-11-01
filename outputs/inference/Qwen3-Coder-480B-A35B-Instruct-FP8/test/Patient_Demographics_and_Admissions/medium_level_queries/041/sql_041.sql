WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 88 AND 98
    AND p.gender = 'M'
    AND a.admission_type = 'ELECTIVE'
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Died in hospital'
      WHEN discharge_location LIKE 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/Rehab/LTACH'
      ELSE 'Other'
    END AS outcome_group
  FROM
    cohort
)
SELECT
  outcome_group,
  COUNT(*) AS n_patients,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS pct_los_le_7_days
FROM
  discharge_groups
WHERE
  outcome_group IN ('Home', 'SNF/Rehab/LTACH', 'Died in hospital')
GROUP BY
  outcome_group
ORDER BY
  outcome_group;