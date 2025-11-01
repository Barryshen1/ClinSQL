WITH gi_bleed AS (
  SELECT
    d.hadm_id,
    MAX(CASE
      WHEN d.icd_code IN ('K25', 'K26', 'K27', 'K28', 'K22.0', 'K22.1', 'K22.2', 'K22.3', 'K22.4', 'K22.5', 'K22.8', 'K22.9') THEN 'Upper'
      WHEN d.icd_code IN ('K62.5', 'K62.8', 'K55.0', 'K55.1', 'K55.2', 'K55.3', 'K55.4', 'K55.5', 'K55.6', 'K55.8', 'K55.9', 'K92.2') THEN 'Lower'
      ELSE NULL
    END) AS gi_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code IN (
    'K25', 'K26', 'K27', 'K28', 'K22.0', 'K22.1', 'K22.2', 'K22.3', 'K22.4', 'K22.5', 'K22.8', 'K22.9',
    'K62.5', 'K62.8', 'K55.0', 'K55.1', 'K55.2', 'K55.3', 'K55.4', 'K55.5', 'K55.6', 'K55.8', 'K55.9', 'K92.2'
  )
  GROUP BY d.hadm_id
),
admissions_with_gi AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    g.gi_type,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN gi_bleed g ON a.hadm_id = g.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
los_categories AS (
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 2 THEN '1-2'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 3 AND 5 THEN '3-5'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 6 AND 9 THEN '6-9'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) >= 10 THEN '>=10'
      ELSE 'Other'
    END AS los_category
  FROM admissions_with_gi
),
icu_status AS (
  SELECT
    l.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = l.hadm_id
          AND i.intime >= l.admittime
          AND i.intime <= l.admittime + INTERVAL 24 HOUR
      ) THEN 'Yes'
      ELSE 'No'
    END AS day1_icu,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i
        WHERE i.hadm_id = l.hadm_id
      ) THEN 'Yes'
      ELSE 'No'
    END AS any_icu
  FROM los_categories l
)
SELECT
  gi_type,
  los_category,
  day1_icu,
  ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_rate,
  ROUND(SUM(CASE WHEN any_icu = 'Yes' THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS icu_admission_rate
FROM icu_status
GROUP BY gi_type, los_category, day1_icu
ORDER BY gi_type, los_category, day1_icu;