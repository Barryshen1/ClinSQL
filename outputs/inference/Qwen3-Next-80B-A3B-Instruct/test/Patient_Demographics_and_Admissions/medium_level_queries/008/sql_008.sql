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
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'ELECTIVE'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND p.anchor_age IS NOT NULL
),
discharge_categories AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'PSYCH', 'ALTERNATE HEALTH CARE') THEN 'facility'
      ELSE 'other'
    END AS discharge_category
  FROM
    filtered_admissions
  WHERE
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME CARE', 'HOME WITH HEALTH SERVICES', 'HOME WITH HOSPICE') THEN 'home'
      WHEN discharge_location IN ('SNF', 'REHAB', 'LONG TERM CARE', 'OTHER FACILITY', 'PSYCH', 'ALTERNATE HEALTH CARE') THEN 'facility'
      ELSE 'other'
    END IN ('home', 'facility', 'in-hospital death')
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(los_days, 0.5) AS median_los_p50,
  PERCENTILE_CONT(los_days, 0.75) AS p75_los,
  PERCENTILE_CONT(los_days, 0.90) AS p90_los,
  AVG(CASE WHEN los_days <= 7 THEN 1.0 ELSE 0 END) * 100 AS percentile_rank_7_days
FROM
  discharge_categories
GROUP BY
  discharge_category
ORDER BY
  discharge_category;