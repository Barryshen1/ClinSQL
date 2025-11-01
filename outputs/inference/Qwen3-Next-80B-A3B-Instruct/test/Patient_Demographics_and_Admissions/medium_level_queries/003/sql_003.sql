WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_groups AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      ELSE NULL
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      ELSE NULL
    END IS NOT NULL
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 99)[OFFSET(24)] AS p25_los,
  APPROX_QUANTILES(los_days, 99)[OFFSET(49)] AS median_los,
  APPROX_QUANTILES(los_days, 99)[OFFSET(74)] AS p75_los,
  APPROX_QUANTILES(los_days, 99)[OFFSET(89)] AS p90_los,
  AVG(CASE WHEN los_days <= 14 THEN 1.0 ELSE 0 END) AS percent_los_le_14
FROM
  discharge_groups
GROUP BY
  discharge_category
ORDER BY
  discharge_category;