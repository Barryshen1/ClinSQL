WITH cohort AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    discharge_location,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND adm.admission_type != 'EMERGENCY'
),
discharge_groups AS (
  SELECT
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE NULL
    END AS discharge_group
  FROM
    cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  100 * AVG(CASE WHEN los_days <= 14 THEN 1 ELSE 0 END) AS pct_le_14_days
FROM
  discharge_groups
WHERE
  discharge_group IS NOT NULL
GROUP BY
  discharge_group
ORDER BY
  discharge_group;