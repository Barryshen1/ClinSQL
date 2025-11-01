WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    COALESCE(a.deathtime, a.dischtime) AS endtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.admittime IS NOT NULL
    AND COALESCE(a.deathtime, a.dischtime) IS NOT NULL
    AND DATETIME_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) >= 0
),
categorized AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      ELSE 'OTHER'
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      ELSE 'OTHER'
    END IN ('HOME', 'HOSPICE', 'IN-HOSPITAL DEATH')
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  (COUNTIF(los_days <= 10) * 100.0 / COUNT(*)) AS percentile_rank_10_days
FROM
  categorized
GROUP BY
  discharge_category
ORDER BY
  discharge_category;