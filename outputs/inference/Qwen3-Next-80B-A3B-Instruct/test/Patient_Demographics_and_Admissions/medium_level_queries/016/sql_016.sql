WITH filtered_admissions AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    p.anchor_age,
    p.gender,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND i.stay_id IS NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime >= a.admittime
    AND a.discharge_location IS NOT NULL
),
grouped_discharge AS (
  SELECT
    los_days,
    CASE
      WHEN discharge_location IN ('Home', 'Home with Home Care', 'Home with Health Services', 'Home with Hospice') THEN 'Home'
      WHEN discharge_location = 'Hospice' THEN 'Hospice'
      WHEN discharge_location IN ('Death', 'Expired') THEN 'Death'
      ELSE 'Other'
    END AS discharge_category
  FROM
    filtered_admissions
)
SELECT
  discharge_category,
  PERCENTILE_CONT(los_days, 0.5) AS p50_los,
  PERCENTILE_CONT(los_days, 0.75) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) AS p90_los,
  PERCENTILE_CONT(los_days, 0.95) AS p95_los,
  AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0 END) AS prop_7day_or_less
FROM
  grouped_discharge
WHERE
  discharge_category IN ('Home', 'Hospice', 'Death')
GROUP BY
  discharge_category
ORDER BY
  discharge_category;