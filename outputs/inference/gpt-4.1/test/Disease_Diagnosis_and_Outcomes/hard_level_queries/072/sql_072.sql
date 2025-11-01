WITH
-- 1. ACS ICD codes (ICD-9: 410-414, ICD-10: I20-I25)
acs_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^41[0-4]'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I2[0-5]'))
),

-- 2. Cardiac complication ICD codes (examples: arrhythmia, heart failure, cardiac arrest)
cardiac_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^42[7-9]') -- arrhythmia
      OR REGEXP_CONTAINS(icd_code, r'^428')  -- heart failure
      OR REGEXP_CONTAINS(icd_code, r'^427.5') -- cardiac arrest
    ))
    OR (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I4[7-9]') -- arrhythmia
      OR REGEXP_CONTAINS(icd_code, r'^I50')  -- heart failure
      OR REGEXP_CONTAINS(icd_code, r'^I46')  -- cardiac arrest
    ))
),

-- 3. Neurologic complication ICD codes (examples: stroke, seizure, delirium)
neuro_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^43[0-8]') -- stroke
      OR REGEXP_CONTAINS(icd_code, r'^780.3') -- seizure
      OR REGEXP_CONTAINS(icd_code, r'^293')   -- delirium
    ))
    OR (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I6[0-9]') -- stroke
      OR REGEXP_CONTAINS(icd_code, r'^G40')  -- seizure
      OR REGEXP_CONTAINS(icd_code, r'^F05')  -- delirium
    ))
),

-- 4. All admissions for female, age 67-77, with ICU stay
base_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    pat.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 67 AND 77
),

-- 5. Identify ACS admissions
acs_admissions AS (
  SELECT DISTINCT ba.*
  FROM base_admissions ba
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON ba.hadm_id = dx.hadm_id
  JOIN acs_icd acs
    ON dx.icd_code = acs.icd_code AND dx.icd_version = acs.icd_version
),

-- 6. Identify general inpatient cohort (female, age 67-77, ICU stay, NOT ACS)
general_admissions AS (
  SELECT ba.*
  FROM base_admissions ba
  WHERE ba.hadm_id NOT IN (SELECT hadm_id FROM acs_admissions)
),

-- 7. Charlson Comorbidity Index (CCI) calculation per admission
-- For brevity, use a simple count of comorbidity categories as proxy
cci_map AS (
  SELECT
    icd_code, icd_version,
    CASE
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]')) THEN 'diabetes'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')) THEN 'heart_failure'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^585')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^N18')) THEN 'renal'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^491|^492|^496')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^J4[1-4]')) THEN 'pulmonary'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^571')) OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^K7[0-6]')) THEN 'liver'
      WHEN (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^140|^141|^142|^143|^144|^145|^146|^147|^148|^149|^150|^151|^152|^153|^154|^155|^156|^157|^158|^159')) OR
           (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^C')) THEN 'malignancy'
      ELSE NULL
    END AS cci_cat
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
),

admission_cci AS (
  SELECT
    dx.hadm_id,
    COUNT(DISTINCT cci_map.cci_cat) AS cci_score
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN cci_map
    ON dx.icd_code = cci_map.icd_code AND dx.icd_version = cci_map.icd_version
  WHERE cci_map.cci_cat IS NOT NULL
  GROUP BY dx.hadm_id
),

-- 8. Cardiac complications per admission
admission_cardiac_comp AS (
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN cardiac_icd cdx
    ON dx.icd_code = cdx.icd_code AND dx.icd_version = cdx.icd_version
),

-- 9. Neurologic complications per admission
admission_neuro_comp AS (
  SELECT DISTINCT dx.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  JOIN neuro_icd ndx
    ON dx.icd_code = ndx.icd_code AND dx.icd_version = ndx.icd_version
),

-- 10. Calculate metrics for ACS cohort
acs_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.dod,
    IFNULL(acci.cci_score, 0) AS cci_score,
    -- 30-day mortality: death within 30 days of admittime
    CASE
      WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN a.dod IS NOT NULL AND TIMESTAMP_DIFF(a.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    -- Cardiac complication
    CASE WHEN acc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS cardiac_complication,
    -- Neurologic complication
    CASE WHEN anc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS neuro_complication,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24) AS los_days
  FROM acs_admissions a
  LEFT JOIN admission_cci acci ON a.hadm_id = acci.hadm_id
  LEFT JOIN admission_cardiac_comp acc ON a.hadm_id = acc.hadm_id
  LEFT JOIN admission_neuro_comp anc ON a.hadm_id = anc.hadm_id
),

-- 11. Calculate metrics for general inpatient cohort
general_metrics AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.dod,
    IFNULL(acci.cci_score, 0) AS cci_score,
    CASE
      WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN a.dod IS NOT NULL AND TIMESTAMP_DIFF(a.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d,
    CASE WHEN acc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS cardiac_complication,
    CASE WHEN anc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS neuro_complication,
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24) AS los_days
  FROM general_admissions a
  LEFT JOIN admission_cci acci ON a.hadm_id = acci.hadm_id
  LEFT JOIN admission_cardiac_comp acc ON a.hadm_id = acc.hadm_id
  LEFT JOIN admission_neuro_comp anc ON a.hadm_id = anc.hadm_id
),

-- 12. Index patient (72-year-old female)
index_patient AS (
  SELECT *
  FROM acs_metrics
  WHERE anchor_age = 72
  ORDER BY admittime
  LIMIT 1
),

-- 13. Percentile calculations for index patient
percentiles AS (
  SELECT
    ip.hadm_id,
    ip.subject_id,
    ip.cci_score,
    ip.los_days,
    ip.mortality_30d,
    -- CCI percentile among ACS cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM acs_metrics WHERE cci_score <= ip.cci_score
    ) / (SELECT COUNT(*) FROM acs_metrics), 1) AS cci_percentile_acs,
    -- LOS percentile among ACS cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM acs_metrics WHERE los_days <= ip.los_days
    ) / (SELECT COUNT(*) FROM acs_metrics), 1) AS los_percentile_acs,
    -- Mortality percentile among ACS cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM acs_metrics WHERE mortality_30d <= ip.mortality_30d
    ) / (SELECT COUNT(*) FROM acs_metrics), 1) AS mortality_percentile_acs,
    -- CCI percentile among general cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM general_metrics WHERE cci_score <= ip.cci_score
    ) / (SELECT COUNT(*) FROM general_metrics), 1) AS cci_percentile_general,
    -- LOS percentile among general cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM general_metrics WHERE los_days <= ip.los_days
    ) / (SELECT COUNT(*) FROM general_metrics), 1) AS los_percentile_general,
    -- Mortality percentile among general cohort
    ROUND(100 * (
      SELECT COUNT(*) FROM general_metrics WHERE mortality_30d <= ip.mortality_30d
    ) / (SELECT COUNT(*) FROM general_metrics), 1) AS mortality_percentile_general
  FROM index_patient ip
)

-- Final output: summary metrics and index patient percentiles in one query
SELECT
  'ACS cohort' AS cohort_or_label,
  COUNT(*) AS n_patients,
  ROUND(AVG(cci_score),2) AS mean_risk_score,
  ROUND(AVG(mortality_30d)*100,2) AS mortality_30d_pct,
  ROUND(SUM(cardiac_complication)/COUNT(*)*100,2) AS cardiac_complication_pct,
  ROUND(SUM(neuro_complication)/COUNT(*)*100,2) AS neuro_complication_pct,
  ROUND(AVG(los_days),2) AS mean_los_survivors,
  NULL AS cci_score,
  NULL AS los_days,
  NULL AS mortality_30d,
  NULL AS cci_percentile_acs,
  NULL AS los_percentile_acs,
  NULL AS mortality_percentile_acs,
  NULL AS cci_percentile_general,
  NULL AS los_percentile_general,
  NULL AS mortality_percentile_general
FROM acs_metrics
WHERE (deathtime IS NULL OR TIMESTAMP_DIFF(deathtime, admittime, DAY) > 30)

UNION ALL

SELECT
  'General inpatient cohort' AS cohort_or_label,
  COUNT(*) AS n_patients,
  ROUND(AVG(cci_score),2) AS mean_risk_score,
  ROUND(AVG(mortality_30d)*100,2) AS mortality_30d_pct,
  ROUND(SUM(cardiac_complication)/COUNT(*)*100,2) AS cardiac_complication_pct,
  ROUND(SUM(neuro_complication)/COUNT(*)*100,2) AS neuro_complication_pct,
  ROUND(AVG(los_days),2) AS mean_los_survivors,
  NULL AS cci_score,
  NULL AS los_days,
  NULL AS mortality_30d,
  NULL AS cci_percentile_acs,
  NULL AS los_percentile_acs,
  NULL AS mortality_percentile_acs,
  NULL AS cci_percentile_general,
  NULL AS los_percentile_general,
  NULL AS mortality_percentile_general
FROM general_metrics
WHERE (deathtime IS NULL OR TIMESTAMP_DIFF(deathtime, admittime, DAY) > 30)

UNION ALL

SELECT
  'Index patient (72F ACS)' AS cohort_or_label,
  NULL AS n_patients,
  NULL AS mean_risk_score,
  NULL AS mortality_30d_pct,
  NULL AS cardiac_complication_pct,
  NULL AS neuro_complication_pct,
  NULL AS mean_los_survivors,
  cci_score,
  los_days,
  mortality_30d,
  cci_percentile_acs,
  los_percentile_acs,
  mortality_percentile_acs,
  cci_percentile_general,
  los_percentile_general,
  mortality_percentile_general
FROM percentiles
;