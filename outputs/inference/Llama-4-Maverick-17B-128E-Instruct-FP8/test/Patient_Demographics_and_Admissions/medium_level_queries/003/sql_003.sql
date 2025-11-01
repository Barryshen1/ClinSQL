WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 80 AND 90
),
filtered_admissions AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.discharge_location,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN filtered_patients pat ON adm.subject_id = pat.subject_id
  WHERE adm.admission_type != 'EMERGENCY'
),
discharge_categories AS (
  SELECT 
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      ELSE 'other'
    END AS discharge_category
  FROM filtered_admissions
),
categorized_los AS (
  SELECT 
    discharge_category,
    los_days,
    CASE WHEN los_days <= 14 THEN 1 ELSE 0 END AS los_le_14
  FROM discharge_categories
  WHERE discharge_category IN ('home', 'hospice', 'in-hospital death')
)

SELECT 
  discharge_category,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
  AVG(los_le_14) * 100 AS percent_los_le_14
FROM categorized_los
GROUP BY discharge_category
ORDER BY discharge_category;