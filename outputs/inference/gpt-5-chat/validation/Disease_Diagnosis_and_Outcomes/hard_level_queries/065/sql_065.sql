WITH dvt_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(icd_code, r'^453')
     OR REGEXP_CONTAINS(icd_code, r'^I82')
),
complication_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(icd_code, r'^038')
     OR REGEXP_CONTAINS(icd_code, r'^A41')
     OR REGEXP_CONTAINS(icd_code, r'^518')
     OR REGEXP_CONTAINS(icd_code, r'^J96')
),
comorbidity_counts AS (
  SELECT di.subject_id, di.hadm_id,
         COUNT(DISTINCT di.icd_code) AS comorb_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.subject_id, di.hadm_id
),
complication_flags AS (
  SELECT di.subject_id, di.hadm_id,
         COUNT(DISTINCT di.icd_code) AS comp_count,
         IF(SUM(IF(cc.icd_code IS NOT NULL, 1, 0)) > 0, 1, 0) AS has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  LEFT JOIN complication_codes cc
    ON di.icd_code = cc.icd_code
   AND di.icd_version = cc.icd_version
  GROUP BY di.subject_id, di.hadm_id
),
cohort_dvt AS (
  SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender,
         a.admittime, a.dischtime, p.dod,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         cc.comorb_count,
         cf.has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN dvt_codes dv
    ON di.icd_code = dv.icd_code
   AND di.icd_version = dv.icd_version
  JOIN comorbidity_counts cc
    ON a.subject_id = cc.subject_id
   AND a.hadm_id = cc.hadm_id
  JOIN complication_flags cf
    ON a.subject_id = cf.subject_id
   AND a.hadm_id = cf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND cc.comorb_count >= 5
),
cohort_general AS (
  SELECT a.subject_id, a.hadm_id, p.anchor_age, p.gender,
         a.admittime, a.dischtime, p.dod,
         TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
         cc.comorb_count,
         cf.has_complication
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN comorbidity_counts cc
    ON a.subject_id = cc.subject_id
   AND a.hadm_id = cc.hadm_id
  JOIN complication_flags cf
    ON a.subject_id = cf.subject_id
   AND a.hadm_id = cf.hadm_id
),
stats_dvt AS (
  SELECT 
    APPROX_QUANTILES(comorb_count, 100)[OFFSET(50)] AS median_comorb_count,
    APPROX_QUANTILES(comorb_count, 100)[OFFSET(75)] 
      - APPROX_QUANTILES(comorb_count, 100)[OFFSET(25)] AS iqr_comorb_count,
    SUM(IF(dod IS NOT NULL AND DATE_DIFF(DATE(dod), DATE(dischtime), DAY) <= 90, 1, 0)) / COUNT(*) AS mortality_90d,
    SUM(has_complication) / COUNT(*) AS complication_rate
  FROM cohort_dvt
),
stats_general AS (
  SELECT
    SUM(has_complication) / COUNT(*) AS complication_rate,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_survivors
  FROM cohort_general
  WHERE dod IS NULL OR DATE_DIFF(DATE(dod), DATE(dischtime), DAY) > 0
),
patient_risk AS (
  SELECT subject_id, hadm_id, comorb_count
  FROM cohort_dvt
  WHERE anchor_age = 76
  LIMIT 1
),
percentile_rank AS (
  SELECT 
    p.subject_id, 
    p.hadm_id,
    p.comorb_count,
    100 * SUM(IF(c.comorb_count <= p.comorb_count, 1, 0)) / COUNT(*) AS risk_percentile
  FROM patient_risk p
  CROSS JOIN cohort_dvt c
)
SELECT 
  sdv.median_comorb_count, 
  sdv.iqr_comorb_count, 
  sdv.mortality_90d,
  sdv.complication_rate AS dvt_complication_rate,
  sgen.complication_rate AS general_complication_rate,
  sgen.median_los_survivors AS general_median_los_survivors,
  pr.comorb_count AS patient_comorb_count,
  pr.risk_percentile
FROM stats_dvt sdv
CROSS JOIN stats_general sgen
CROSS JOIN percentile_rank pr;