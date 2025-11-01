WITH icu_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE hadm_id IS NOT NULL
)

SELECT
  CASE
    WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 'Discharged to Hospice'
    WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Discharged Home'
  END AS discharge_category,
  COUNT(*) AS n_admissions,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0), 2) AS mean_los_days,
  ROUND(STDDEV_SAMP(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0), 2) AS sd_los_days
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
LEFT JOIN icu_hadms i
  ON a.hadm_id = i.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 75 AND 85
  AND a.hadm_id IS NOT NULL
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL
  AND TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) >= 0
  AND i.hadm_id IS NULL -- exclude admissions with any ICU stay
  AND (
    a.hospital_expire_flag = 1
    OR LOWER(a.discharge_location) LIKE '%hospice%'
    OR LOWER(a.discharge_location) LIKE '%home%'
  )
GROUP BY discharge_category
ORDER BY discharge_category;