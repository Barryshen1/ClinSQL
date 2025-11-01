WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.dischtime,
    adm.admittime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_admission,
    -- Calculate LOS in fractional days
    DATETIME_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pt.gender = 'M'
),
categorized AS (
  SELECT
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      WHEN discharge_location = 'HOME' THEN 'home'
      ELSE 'facility'
    END AS discharge_category
  FROM
    cohort
  WHERE
    age_admission BETWEEN 38 AND 48
)
SELECT
  discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(50)], 2) AS median_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(75)], 2) AS p75_los_days,
  ROUND(APPROX_QUANTILES(los_days, 100)[OFFSET(90)], 2) AS p90_los_days
FROM
  categorized
GROUP BY
  discharge_category
ORDER BY
  discharge_category;