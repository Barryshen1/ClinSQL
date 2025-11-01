WITH cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.services` s ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_age BETWEEN 49 AND 59
    AND s.curr_service LIKE 'MED%'
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN discharge_location IN ('Home', 'HOME', 'home') THEN 'Home'
      WHEN discharge_location IN ('HOSPICE', 'hospice', 'Home with Home Health', 'home health', 'home with hospice') THEN 'Hospice'
      WHEN discharge_location IN ('DIED', 'DEAD/EXPIRED', 'dead', 'expired') OR hospital_expire_flag = 1 THEN 'In-hospital death'
      ELSE 'Other'
    END AS discharge_group
  FROM cohort
)
SELECT
  discharge_group,
  COUNT(*) AS n_patients,
  COUNTIF(los_days >= 7) / COUNT(*) AS prop_los_ge_7d,
  COUNTIF(los_days >= 14) / COUNT(*) AS prop_los_ge_14d,
  COUNTIF(los_days <= 7) / COUNT(*) AS los_7d_percentile
FROM discharge_groups
GROUP BY discharge_group
HAVING COUNT(*) > 0
ORDER BY discharge_group;