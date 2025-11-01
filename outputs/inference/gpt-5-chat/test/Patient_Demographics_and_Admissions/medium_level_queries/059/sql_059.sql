WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_location,
    a.discharge_location,
    a.hospital_expire_flag,
    -- length of stay in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(a.discharge_location) LIKE '%HOSPICE%' THEN 'Hospice'
      WHEN UPPER(a.discharge_location) IN ('HOME', 'HOME HEALTH CARE') THEN 'Home'
      ELSE 'Other'
    END AS discharge_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND UPPER(a.admission_location) LIKE '%TRANSFER%'
    AND UPPER(a.admission_location) LIKE '%HOSPITAL%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS los_ge_7_count,
  SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS los_ge_7_proportion,
  SAFE_DIVIDE(SUM(CASE WHEN los_days <= 7 THEN 1 ELSE 0 END), COUNT(*)) AS percentile_7day
FROM cohort
WHERE discharge_category IN ('Home', 'Hospice', 'In-hospital death')
GROUP BY discharge_category
ORDER BY discharge_category;