WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime >= a.admittime
),
discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTAC', 'SKILLED NURSING FACILITY') THEN 'SNF/Rehab/LTACH'
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
      ELSE 'Other'
    END AS discharge_group
  FROM
    cohort
),
filtered_groups AS (
  SELECT *
  FROM discharge_groups
  WHERE discharge_group IN ('Home', 'SNF/Rehab/LTACH', 'In-Hospital Death')
)
SELECT
  discharge_group,
  COUNT(*) AS n_patients,
  AVG(CASE WHEN los >= 7 THEN 1.0 ELSE 0.0 END) AS prop_los_ge_7,
  APPROX_QUANTILES(los, 100)[OFFSET(14)] AS los_14th_percentile
FROM
  filtered_groups
GROUP BY
  discharge_group
ORDER BY
  discharge_group;