WITH non_icu_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.transfers t
      WHERE t.hadm_id = a.hadm_id
        AND t.careunit LIKE '%ICU%'
    )
),
discharge_groups AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
      WHEN discharge_location = 'HOSPICE' THEN 'Discharged to Hospice'
      WHEN discharge_location = 'HOME' THEN 'Discharged Home'
      ELSE NULL
    END AS discharge_category
  FROM non_icu_admissions
  WHERE discharge_location IN ('HOME', 'HOSPICE') OR hospital_expire_flag = 1
)
SELECT
  discharge_category,
  AVG(los_days) AS mean_los_days,
  STDDEV(los_days) AS stddev_los_days
FROM discharge_groups
WHERE discharge_category IS NOT NULL
GROUP BY discharge_category
ORDER BY discharge_category;