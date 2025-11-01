WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location IN ('ED', 'Emergency Department')
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
discharge_categories AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE', 'HOME WITH HOSPICE AND HOME CARE') THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM
    cohort
)
SELECT
  discharge_category,
  AVG(CASE WHEN los_days >= 7 THEN 1.0 ELSE 0.0 END) AS proportion_los_ge_7,
  APPROX_QUANTILES(los_days, 100)[OFFSET(10)] AS percentile_10th_los
FROM
  discharge_categories
GROUP BY
  discharge_category
ORDER BY
  discharge_category;