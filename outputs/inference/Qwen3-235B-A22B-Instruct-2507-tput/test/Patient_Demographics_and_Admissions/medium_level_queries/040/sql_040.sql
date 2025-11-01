WITH surgical_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON a.hadm_id = p.hadm_id
),
cohort AS (
  SELECT
    a.hadm_id,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN surgical_admissions s
    ON a.hadm_id = s.hadm_id
  WHERE p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 70 AND 80
),
discharge_groups AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location IN ('HOME', 'HOME WITH HOME IV PROVIDER') THEN 'Home'
      WHEN discharge_location IN (
        'SKILLED NURSING FACILITY', 'SNF', 'REHAB', 'REHAB UNIT', 'LONG TERM CARE HOSPITAL', 'LTACH'
      ) THEN 'Facility'
      ELSE NULL
    END AS discharge_category
  FROM cohort
  WHERE discharge_location IS NOT NULL
),
summary AS (
  SELECT
    discharge_category,
    COUNT(*) AS total,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_los_ge7,
    SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS count_los_ge14
  FROM discharge_groups
  WHERE discharge_category IS NOT NULL
  GROUP BY discharge_category
)
SELECT
  discharge_category,
  ROUND(SAFE_DIVIDE(count_los_ge7, total), 3) AS prop_los_ge7,
  ROUND(SAFE_DIVIDE(count_los_ge14, total), 3) AS prop_los_ge14,
  total
FROM summary
ORDER BY discharge_category;