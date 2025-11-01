WITH
-- List of PE ICD codes (ICD-10 and ICD-9)
pe_icd_codes AS (
  SELECT 'I26' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I260', 10 UNION ALL
  SELECT 'I269', 10 UNION ALL
  SELECT '4151', 9 UNION ALL
  SELECT '41519', 9 UNION ALL
  SELECT '41513', 9
),
-- List of QT-prolonging drugs (example, expand as needed)
qt_drugs AS (
  SELECT 'amiodarone' AS drug UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'haloperidol' UNION ALL
  SELECT 'ciprofloxacin' UNION ALL
  SELECT 'azithromycin'
),
-- List of bleeding-risk drugs (example, expand as needed)
bleed_drugs AS (
  SELECT 'warfarin' AS drug UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'aspirin' UNION ALL
  SELECT 'clopidogrel'
),
-- Cohort: Female inpatients aged 74-84 with PE
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN pe_icd_codes pe
      ON d.icd_code LIKE CONCAT(pe.icd_code, '%') AND d.icd_version = pe.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),
-- Medication complexity in first 24h
meds_24h AS (
  SELECT
    c.hadm_id,
    LOWER(TRIM(pr.drug)) AS drug
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
-- Complexity per admission
complexity AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS med_complexity
  FROM meds_24h
  GROUP BY hadm_id
),
-- Prevalence of QT-prolonging drugs
qt_prevalence AS (
  SELECT
    m.hadm_id,
    COUNT(DISTINCT m.drug) AS qt_drug_count,
    CASE WHEN COUNT(DISTINCT m.drug) > 0 THEN 1 ELSE 0 END AS qt_any
  FROM meds_24h m
    JOIN qt_drugs q ON m.drug = q.drug
  GROUP BY m.hadm_id
),
-- Prevalence of bleeding-risk drugs
bleed_prevalence AS (
  SELECT
    m.hadm_id,
    COUNT(DISTINCT m.drug) AS bleed_drug_count,
    CASE WHEN COUNT(DISTINCT m.drug) > 0 THEN 1 ELSE 0 END AS bleed_any
  FROM meds_24h m
    JOIN bleed_drugs b ON m.drug = b.drug
  GROUP BY m.hadm_id
),
-- ICU stays
icu_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
-- LOS per admission
los AS (
  SELECT
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort c
),
-- Top quartile LOS threshold
los_quartile AS (
  SELECT
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_q3
  FROM los
),
-- Combine all metrics per admission
all_metrics AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.deathtime,
    c.hospital_expire_flag,
    comp.med_complexity,
    IFNULL(qt.qt_any, 0) AS qt_any,
    IFNULL(qt.qt_drug_count, 0) AS qt_drug_count,
    IFNULL(bleed.bleed_any, 0) AS bleed_any,
    IFNULL(bleed.bleed_drug_count, 0) AS bleed_drug_count,
    los.los_days,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM cohort c
    LEFT JOIN complexity comp ON c.hadm_id = comp.hadm_id
    LEFT JOIN qt_prevalence qt ON c.hadm_id = qt.hadm_id
    LEFT JOIN bleed_prevalence bleed ON c.hadm_id = bleed.hadm_id
    LEFT JOIN los ON c.hadm_id = los.hadm_id
    LEFT JOIN icu_admissions icu ON c.hadm_id = icu.hadm_id
),
-- Complexity percentiles
complexity_percentiles AS (
  SELECT
    hadm_id,
    med_complexity,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS complexity_percentile
  FROM all_metrics
)
-- Final output
SELECT
  -- Overall complexity stats
  COUNT(*) AS n_admissions,
  ROUND(AVG(all_metrics.med_complexity),2) AS mean_complexity,
  MIN(all_metrics.med_complexity) AS min_complexity,
  MAX(all_metrics.med_complexity) AS max_complexity,
  ROUND(STDDEV(all_metrics.med_complexity),2) AS sd_complexity,
  -- Prevalence of QT-prolonging drugs
  ROUND(AVG(all_metrics.qt_any)*100,1) AS pct_qt_any,
  ROUND(AVG(all_metrics.qt_drug_count),2) AS mean_qt_drugs,
  -- Prevalence of bleeding-risk drugs
  ROUND(AVG(all_metrics.bleed_any)*100,1) AS pct_bleed_any,
  ROUND(AVG(all_metrics.bleed_drug_count),2) AS mean_bleed_drugs,
  -- Mean complexity percentile
  ROUND(AVG(cp.complexity_percentile)*100,1) AS mean_complexity_percentile,
  -- ICU comparison
  ROUND(AVG(CASE WHEN all_metrics.had_icu=1 THEN all_metrics.med_complexity ELSE NULL END),2) AS mean_complexity_icu,
  ROUND(AVG(CASE WHEN all_metrics.had_icu=0 THEN all_metrics.med_complexity ELSE NULL END),2) AS mean_complexity_nonicu,
  ROUND(AVG(CASE WHEN all_metrics.had_icu=1 THEN all_metrics.qt_any ELSE NULL END)*100,1) AS pct_qt_any_icu,
  ROUND(AVG(CASE WHEN all_metrics.had_icu=0 THEN all_metrics.qt_any ELSE NULL END)*100,1) AS pct_qt_any_nonicu,
  ROUND(AVG(CASE WHEN all_metrics.had_icu=1 THEN all_metrics.bleed_any ELSE NULL END)*100,1) AS pct_bleed_any_icu,
  ROUND(AVG(CASE WHEN all_metrics.had_icu=0 THEN all_metrics.bleed_any ELSE NULL END)*100,1) AS pct_bleed_any_nonicu,
  -- Top quartile LOS and mortality
  ROUND(AVG(CASE WHEN all_metrics.los_days >= (SELECT los_q3 FROM los_quartile) THEN all_metrics.hospital_expire_flag ELSE NULL END)*100,1) AS mortality_top_quartile_los,
  COUNTIF(all_metrics.los_days >= (SELECT los_q3 FROM los_quartile)) AS n_top_quartile_los
FROM all_metrics
LEFT JOIN complexity_percentiles cp ON all_metrics.hadm_id = cp.hadm_id
;