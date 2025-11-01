WITH
-- Define age range and gender filter
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS current_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 74 AND 84
),

-- Get ICU stays information
icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    intime,
    outtime,
    los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Get medications within first 24 hours of admission
first_24h_meds AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    pr.drug,
    pr.drug_type,
    pr.starttime,
    pr.stoptime,
    -- Flag for QT-prolonging drugs (simplified list)
    CASE
      WHEN LOWER(pr.drug) LIKE '%amiodarone%'
           OR LOWER(pr.drug) LIKE '%quinidine%'
           OR LOWER(pr.drug) LIKE '%sotalol%'
           OR LOWER(pr.drug) LIKE '%erythromycin%'
           OR LOWER(pr.drug) LIKE '%ciprofloxacin%'
           OR LOWER(pr.drug) LIKE '%haloperidol%'
      THEN 1
      ELSE 0
    END AS is_qt_prolonging,
    -- Flag for bleeding-risk drugs (simplified list)
    CASE
      WHEN LOWER(pr.drug) LIKE '%warfarin%'
           OR LOWER(pr.drug) LIKE '%heparin%'
           OR LOWER(pr.drug) LIKE '%aspirin%'
           OR LOWER(pr.drug) LIKE '%clopidogrel%'
           OR LOWER(pr.drug) LIKE '%rivaroxaban%'
           OR LOWER(pr.drug) LIKE '%apixaban%'
           OR LOWER(pr.drug) LIKE '%dabigatran%'
      THEN 1
      ELSE 0
    END AS is_bleeding_risk
  FROM
    patient_cohort p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    p.subject_id = pr.subject_id AND p.hadm_id = pr.hadm_id
  WHERE
    TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) <= 24
),

-- Aggregate medication complexity metrics per patient
med_complexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT drug) AS unique_med_count,
    SUM(is_qt_prolonging) AS qt_prolonging_count,
    SUM(is_bleeding_risk) AS bleeding_risk_count,
    COUNT(*) AS total_med_orders
  FROM
    first_24h_meds
  GROUP BY
    subject_id, hadm_id
),

-- Combine all information
final_cohort AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.current_age,
    p.los_hours,
    p.hospital_expire_flag,
    m.unique_med_count,
    m.qt_prolonging_count,
    m.bleeding_risk_count,
    m.total_med_orders,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu_stay
  FROM
    patient_cohort p
  LEFT JOIN
    med_complexity m
  ON
    p.subject_id = m.subject_id AND p.hadm_id = m.hadm_id
  LEFT JOIN
    icu_stays i
  ON
    p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
),

-- Pre-calculate LOS quantiles
los_quantiles AS (
  SELECT
    APPROX_QUANTILES(los_hours, 4)[OFFSET(2)] AS q3_los_hours,
    APPROX_QUANTILES(los_hours, 100)[OFFSET(99)] AS p99_los_hours
  FROM
    final_cohort
)

-- Final analysis
SELECT
  -- Overall medication complexity statistics
  'Overall' AS group_name,
  COUNT(*) AS patient_count,
  AVG(unique_med_count) AS avg_med_count,
  MIN(unique_med_count) AS min_med_count,
  MAX(unique_med_count) AS max_med_count,
  STDDEV(unique_med_count) AS sd_med_count,
  AVG(CASE WHEN qt_prolonging_count > 0 THEN 1 ELSE 0 END) AS prevalence_qt_prolonging,
  AVG(CASE WHEN bleeding_risk_count > 0 THEN 1 ELSE 0 END) AS prevalence_bleeding_risk,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(0)] AS q1_med_count,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(1)] AS median_med_count,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(2)] AS q3_med_count,
  APPROX_QUANTILES(unique_med_count, 100)[OFFSET(99)] AS p99_med_count,

  -- Top quartile LOS and mortality
  COUNT(CASE WHEN los_hours > (SELECT q3_los_hours FROM los_quantiles) THEN 1 END) AS top_quartile_los_count,
  AVG(CASE WHEN los_hours > (SELECT q3_los_hours FROM los_quantiles) THEN hospital_expire_flag ELSE NULL END) AS top_quartile_mortality_rate
FROM
  final_cohort

UNION ALL

-- ICU vs non-ICU comparison
SELECT
  CASE WHEN had_icu_stay = 1 THEN 'ICU Patients' ELSE 'Non-ICU Patients' END AS group_name,
  COUNT(*) AS patient_count,
  AVG(unique_med_count) AS avg_med_count,
  MIN(unique_med_count) AS min_med_count,
  MAX(unique_med_count) AS max_med_count,
  STDDEV(unique_med_count) AS sd_med_count,
  AVG(CASE WHEN qt_prolonging_count > 0 THEN 1 ELSE 0 END) AS prevalence_qt_prolonging,
  AVG(CASE WHEN bleeding_risk_count > 0 THEN 1 ELSE 0 END) AS prevalence_bleeding_risk,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(0)] AS q1_med_count,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(1)] AS median_med_count,
  APPROX_QUANTILES(unique_med_count, 4)[OFFSET(2)] AS q3_med_count,
  APPROX_QUANTILES(unique_med_count, 100)[OFFSET(99)] AS p99_med_count,
  COUNT(CASE WHEN los_hours > (SELECT q3_los_hours FROM los_quantiles) THEN 1 END) AS top_quartile_los_count,
  AVG(CASE WHEN los_hours > (SELECT q3_los_hours FROM los_quantiles) THEN hospital_expire_flag ELSE NULL END) AS top_quartile_mortality_rate
FROM
  final_cohort
GROUP BY
  had_icu_stay
ORDER BY
  group_name;