WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
),
discharge_groups AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LTACH', 'LONG TERM CARE', 'FACILITY', 'OTHER') THEN 'SNF/rehab/LTACH'
      ELSE 'other'
    END AS discharge_group
  FROM
    patient_admissions
)
SELECT
  discharge_group,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS proportion_LOS_ge_7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(14)] AS percentile_14th_LOS
FROM
  discharge_groups
WHERE
  discharge_group IN ('home', 'SNF/rehab/LTACH', 'in-hospital death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;