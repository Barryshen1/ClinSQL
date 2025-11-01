WITH base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag AS mortality,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 74 AND 84
),
qt_drug_list AS (
  SELECT 'Amiodarone' AS drug
  UNION ALL SELECT 'Sotalol'
  UNION ALL SELECT 'Dofetilide'
  UNION ALL SELECT 'Quinidine'
  UNION ALL SELECT 'Procainamide'
),
bleeding_drug_list AS (
  SELECT 'Warfarin' AS drug
  UNION ALL SELECT 'Apixaban'
  UNION ALL SELECT 'Rivaroxaban'
  UNION ALL SELECT 'Dabigatran'
  UNION ALL SELECT 'Clopidogrel'
),
med_metrics AS (
  SELECT
    b.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity,
    MAX(CASE WHEN q.drug IS NOT NULL THEN 1 ELSE 0 END) AS qt_flag,
    MAX(CASE WHEN bl.drug IS NOT NULL THEN 1 ELSE 0 END) AS bleeding_flag
  FROM base_cohort b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON b.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN b.admittime AND DATETIME_ADD(b.admittime, INTERVAL 1 DAY)
  LEFT JOIN qt_drug_list q 
    ON pr.drug = q.drug
  LEFT JOIN bleeding_drug_list bl 
    ON pr.drug = bl.drug
  GROUP BY b.hadm_id
),
combined AS (
  SELECT
    b.icu_flag,
    b.los_days,
    b.mortality,
    m.complexity,
    m.qt_flag,
    m.bleeding_flag
  FROM base_cohort b
  LEFT JOIN med_metrics m 
    ON b.hadm_id = m.hadm_id
)
SELECT
  icu_flag,
  COUNT(*) AS n_patients,
  AVG(complexity) AS mean_complexity,
  MIN(complexity) AS min_complexity,
  MAX(complexity) AS max_complexity,
  STDDEV(complexity) AS sd_complexity,
  AVG(qt_flag) AS qt_prevalence,
  AVG(bleeding_flag) AS bleeding_prevalence,
  APPROX_QUANTILES(complexity, 100)[OFFSET(25)] AS complexity_25,
  APPROX_QUANTILES(complexity, 100)[OFFSET(50)] AS complexity_50,
  APPROX_QUANTILES(complexity, 100)[OFFSET(75)] AS complexity_75,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75,
  AVG(mortality) AS mortality_rate
FROM combined
GROUP BY icu_flag;