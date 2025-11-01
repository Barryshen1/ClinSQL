WITH cohort_patients AS (
  -- Female patients aged 74-84
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND p.anchor_age IS NOT NULL
),
admissions AS (
  -- Qualifying admissions
  SELECT a.*
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_patients cp ON a.subject_id = cp.subject_id
),
med_orders AS (
  -- Prescriptions within first 24h
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    pr.pharmacy_id,
    pr.drug,
    pr.doses_per_24_hrs
  FROM admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON a.subject_id = pr.subject_id 
    AND a.hadm_id = pr.hadm_id
  WHERE pr.starttime >= a.admittime 
    AND pr.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND pr.drug IS NOT NULL
),
med_complexity AS (
  -- Aggregate meds per admission: count distinct drugs (MRCI proxy)
  SELECT 
    mo.subject_id,
    mo.hadm_id,
    mo.admittime,
    COUNT(DISTINCT mo.drug) AS med_count,
    -- QT-prolonging flag (common examples)
    MAX(CASE WHEN LOWER(mo.drug) LIKE ANY(
      '%amiodarone%', '%sotalol%', '%haloperidol%', '%ondansetron%', '%methadone%'
    ) THEN 1 ELSE 0 END) AS has_qt_prolonging,
    -- Bleeding-risk flag (anticoag/antiplatelet examples)
    MAX(CASE WHEN LOWER(mo.drug) LIKE ANY(
      '%warfarin%', '%heparin%', '%enoxaparin%', '%aspirin%', '%clopidogrel%'
    ) THEN 1 ELSE 0 END) AS has_bleeding_risk
  FROM med_orders mo
  GROUP BY mo.subject_id, mo.hadm_id, mo.admittime
),
icu_flag AS (
  -- Flag admissions with ICU stay overlapping first 24h
  SELECT 
    mc.subject_id,
    mc.hadm_id,
    mc.admittime,
    mc.med_count,
    mc.has_qt_prolonging,
    mc.has_bleeding_risk,
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
      WHERE icu.subject_id = mc.subject_id
        AND icu.hadm_id = mc.hadm_id
        AND icu.intime < TIMESTAMP_ADD(mc.admittime, INTERVAL 24 HOUR)
        AND icu.outtime > mc.admittime
    ) THEN 1 ELSE 0 END AS has_icu
  FROM med_complexity mc
),
all_female_cohort AS (
  -- Broader cohort for percentiles (all female 74-84 admissions, even without meds)
  SELECT a.hadm_id, COUNT(DISTINCT pr.drug) AS med_count_all
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON (
    a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
    AND pr.starttime >= a.admittime AND pr.starttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND pr.drug IS NOT NULL
  )
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 74 AND 84 AND p.anchor_age IS NOT NULL
  GROUP BY a.hadm_id
),
percentiles AS (
  -- Compute percentiles relative to all female cohort
  SELECT 
    if.subject_id,
    if.hadm_id,
    if.admittime,
    if.med_count,
    if.has_qt_prolonging,
    if.has_bleeding_risk,
    if.has_icu,
    PERCENT_RANK() OVER (ORDER BY afc.med_count_all ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS complexity_percentile,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM icu_flag if
  INNER JOIN all_female_cohort afc ON if.hadm_id = afc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON if.hadm_id = a.hadm_id
)
-- Main results
SELECT 
  -- Complexity distribution
  AVG(med_count) AS mean_complexity,
  MIN(med_count) AS min_complexity,
  MAX(med_count) AS max_complexity,
  STDDEV(med_count) AS sd_complexity,
  -- Mean percentile
  AVG(complexity_percentile) AS mean_complexity_percentile,
  -- Prevalences
  AVG(has_qt_prolonging) AS qt_prolonging_prevalence,
  AVG(has_bleeding_risk) AS bleeding_risk_prevalence,
  -- ICU comparison (stratified)
  AVG(CASE WHEN has_icu = 1 THEN med_count END) AS mean_complexity_icu,
  AVG(CASE WHEN has_icu = 1 THEN has_qt_prolonging END) AS qt_prevalence_icu,
  AVG(CASE WHEN has_icu = 1 THEN has_bleeding_risk END) AS bleeding_prevalence_icu,
  AVG(CASE WHEN has_icu = 0 THEN med_count END) AS mean_complexity_non_icu,
  AVG(CASE WHEN has_icu = 0 THEN has_qt_prolonging END) AS qt_prevalence_non_icu,
  AVG(CASE WHEN has_icu = 0 THEN has_bleeding_risk END) AS bleeding_prevalence_non_icu,
  -- Top-quartile LOS and mortality
  AVG(CASE WHEN med_count >= (SELECT PERCENTILE_CONT(med_count, 0.75) OVER(ORDER BY med_count) FROM percentiles) THEN los_days END) AS mean_los_top_quartile,
  AVG(CASE WHEN med_count >= (SELECT PERCENTILE_CONT(med_count, 0.75) OVER(ORDER BY med_count) FROM percentiles) THEN hospital_expire_flag END) AS mortality_top_quartile
FROM percentiles;