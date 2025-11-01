WITH
-- Define age range and gender filter
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

-- Identify QT-prolonging medications (example list - would need clinical validation)
qt_meds AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) IN (
      'amiodarone', 'quinidine', 'sotalol', 'erythromycin',
      'ciprofloxacin', 'haloperidol', 'methadone', 'ondansetron'
    )
),

-- Identify bleeding-risk medications (example list - would need clinical validation)
bleeding_meds AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) IN (
      'warfarin', 'heparin', 'clopidogrel', 'aspirin',
      'rivaroxaban', 'dabigatran', 'apixaban', 'enoxaparin'
    )
),

-- Calculate medication complexity (count of unique medications in first 24 hours)
med_complexity AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS unique_med_count,
    COUNT(DISTINCT pr.drug_type) AS unique_med_types,
    COUNT(DISTINCT pr.route) AS unique_routes
  FROM
    patient_cohort p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE
    TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) <= 24
  GROUP BY
    p.subject_id, p.hadm_id
),

-- Combine all data with interaction flags
combined_data AS (
  SELECT
    p.*,
    CASE WHEN q.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_qt_med,
    CASE WHEN b.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_bleeding_med,
    m.unique_med_count,
    m.unique_med_types,
    m.unique_routes,
    PERCENT_RANK() OVER (ORDER BY p.los_hours) AS los_percentile
  FROM
    patient_cohort p
  LEFT JOIN
    qt_meds q
  ON
    p.subject_id = q.subject_id AND p.hadm_id = q.hadm_id
  LEFT JOIN
    bleeding_meds b
  ON
    p.subject_id = b.subject_id AND p.hadm_id = b.hadm_id
  LEFT JOIN
    med_complexity m
  ON
    p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
),

-- Calculate quartiles for LOS
los_quartiles AS (
  SELECT
    APPROX_QUANTILES(los_hours, 4) AS quartiles
  FROM
    combined_data
)

-- Final results
SELECT
  'QT-prolonging' AS interaction_type,
  AVG(unique_med_count) AS avg_med_count,
  AVG(unique_med_types) AS avg_med_types,
  AVG(unique_routes) AS avg_routes,
  AVG(los_hours) AS avg_los_hours,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  COUNT(*) AS patient_count
FROM
  combined_data
WHERE
  has_qt_med = 1
  AND los_hours >= (SELECT quartiles[OFFSET(2)] FROM los_quartiles)

UNION ALL

SELECT
  'Bleeding-risk' AS interaction_type,
  AVG(unique_med_count) AS avg_med_count,
  AVG(unique_med_types) AS avg_med_types,
  AVG(unique_routes) AS avg_routes,
  AVG(los_hours) AS avg_los_hours,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  COUNT(*) AS patient_count
FROM
  combined_data
WHERE
  has_bleeding_med = 1
  AND los_hours >= (SELECT quartiles[OFFSET(2)] FROM los_quartiles)

UNION ALL

SELECT
  'General' AS interaction_type,
  AVG(unique_med_count) AS avg_med_count,
  AVG(unique_med_types) AS avg_med_types,
  AVG(unique_routes) AS avg_routes,
  AVG(los_hours) AS avg_los_hours,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  COUNT(*) AS patient_count
FROM
  combined_data
WHERE
  has_qt_med = 0
  AND has_bleeding_med = 0
  AND los_hours >= (SELECT quartiles[OFFSET(2)] FROM los_quartiles)
ORDER BY
  interaction_type;