WITH cohort AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.discharge_location,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_location LIKE 'TRANSFER%'
),
categorized AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN discharge_location LIKE '%HOME%' THEN 'home'
      ELSE 'other'
    END AS discharge_category
  FROM
    cohort
),
filtered_cat AS (
  SELECT *
  FROM
    categorized
  WHERE
    discharge_category IN ('home', 'hospice', 'in-hospital death')
),
proportions AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    COUNTIF(los_days >= 7) AS patients_los_ge_7,
    ROUND(100 * COUNTIF(los_days >= 7) / COUNT(*), 1) AS pct_los_ge_7
  FROM
    filtered_cat
  GROUP BY
    discharge_category
),
percentile AS (
  SELECT
    ROUND(
      100 * SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END) / COUNT(*),
      1
    ) AS pct_rank_of_7_day_los
  FROM
    filtered_cat
)
SELECT
  discharge_category,
  total_patients,
  patients_los_ge_7,
  pct_los_ge_7,
  NULL AS pct_rank_of_7_day_los
FROM
  proportions

UNION ALL

SELECT
  'overall' AS discharge_category,
  NULL AS total_patients,
  NULL AS patients_los_ge_7,
  NULL AS pct_los_ge_7,
  pct_rank_of_7_day_los
FROM
  percentile
ORDER BY
  discharge_category;