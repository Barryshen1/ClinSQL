WITH dvt_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
         (d.icd_version = 10 AND (
             d.icd_code LIKE 'I82.4%' OR
             d.icd_code LIKE 'I82.3%' OR
             d.icd_code LIKE 'I80.2%' OR
             d.icd_code LIKE 'I80.3%'
           ))
         OR
         (d.icd_version = 9 AND (
             d.icd_code LIKE '453.4%' OR
             d.icd_code LIKE '453.2%' OR
             d.icd_code LIKE '453.8%'
           ))
       )
),

-- 2) Build simple comorbidity flags per hadm_id (CHF, COPD, Diabetes, Renal, Liver, Malignancy)
comorb_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'I50%' OR di.icd_code LIKE '428%'))
               THEN 1 ELSE 0 END) AS chf_flag,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'J44%'))
               THEN 1 ELSE 0 END) AS copd_flag,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'E11%' OR di.icd_code LIKE '250%'))
               THEN 1 ELSE 0 END) AS diab_flag,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'N17%'))
               THEN 1 ELSE 0 END) AS renal_flag,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'K70%'))
               THEN 1 ELSE 0 END) AS liver_flag,
    MAX(CASE
          WHEN (di.icd_version = 10 AND (di.icd_code LIKE 'C00%' OR di.icd_code LIKE 'C97%'))
               THEN 1 ELSE 0 END) AS malig_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY di.hadm_id
),

-- 3) Attach comorbidity flags to each DVT admission and build a simple elix_score
dvt_with_elix AS (
  SELECT
    dvt.subject_id,
    dvt.hadm_id,
    dvt.admittime,
    dvt.dischtime,
    dvt.deathtime,
    dvt.LOS_days,
    COALESCE(cf.chf_flag, 0) +
    COALESCE(cf.copd_flag, 0) +
    COALESCE(cf.diab_flag, 0) +
    COALESCE(cf.renal_flag, 0) +
    COALESCE(cf.liver_flag, 0) +
    COALESCE(cf.malig_flag, 0) AS elix_score
  FROM dvt_admissions dvt
  LEFT JOIN comorb_flags cf ON dvt.hadm_id = cf.hadm_id
),

-- 4) Determine the high-comorbidity subset using 75th percentile threshold
elix_threshold AS (
  SELECT quant[OFFSET(75)] AS p75
  FROM (SELECT APPROX_QUANTILES(elix_score, 100) AS quant
        FROM dvt_with_elix)
),

high_comorb AS (
  SELECT e.*
  FROM dvt_with_elix e
  JOIN elix_threshold t ON e.elix_score >= t.p75
),

-- 5) Major complications per admission (rule-based)
major_comp_per_hadm AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN (icd_version = 10 AND (icd_code LIKE 'A41%' OR icd_code LIKE 'A40%'))
                    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I26%' OR icd_code LIKE 'I50%' OR icd_code LIKE 'I63%'))
               THEN 1 ELSE 0 END) AS major_comp_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

-- 6) Combine high-comorbidity DVT admissions with major-comp flag
high_comorb_with_comp AS (
  SELECT hc.subject_id,
         hc.hadm_id,
         hc.admittime,
         hc.dischtime,
         hc.deathtime,
         hc.LOS_days,
         hc.elix_score,
         mcp.major_comp_flag
  FROM high_comorb hc
  LEFT JOIN major_comp_per_hadm mcp ON hc.hadm_id = mcp.hadm_id
),

-- 7) 90-day mortality for high-comorbidity DVT admissions
death_90 AS (
  SELECT h.*, 
         CASE
           WHEN COALESCE(p.dod, h.deathtime) IS NULL THEN 0
           WHEN TIMESTAMP_DIFF(COALESCE(p.dod, h.deathtime), h.admittime, DAY) <= 90
                AND COALESCE(p.dod, h.deathtime) >= h.admittime
           THEN 1
           ELSE 0
         END AS death_within_90_days
  FROM high_comorb_with_comp h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON h.subject_id = p.subject_id
),

-- 8) General inpatient comparison metrics
-- 8a. General major complications rate (all admissions)
general_major_comp AS (
  SELECT hadm_id,
         MAX(CASE
               WHEN (icd_version = 10 AND (icd_code LIKE 'A41%' OR icd_code LIKE 'A40%'))
                    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I26%' OR icd_code LIKE 'I50%' OR icd_code LIKE 'I63%'))
               THEN 1 ELSE 0 END) AS major_comp_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

general_cohort AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.deathtime,
         -- LOS for all general inpatients
         TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days_all
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

general_survivor_los AS (
  SELECT APPROX_QUANTILES(LOS_days_all, 100)[OFFSET(50)] AS median_survivor_los
  FROM general_cohort
  WHERE deathtime IS NULL
),

index_case AS (
  SELECT *
  FROM high_comorb
  ORDER BY admittime
  LIMIT 1
),

percentile_of_case AS (
  SELECT 100.0 *
         SUM(CASE WHEN h.elix_score <= c.elix_score THEN 1 ELSE 0 END) / COUNT(*) AS percentile
  FROM high_comorb h
  CROSS JOIN index_case c
)

-- 10) Final SELECT: assemble all requested metrics
SELECT
  (SELECT COUNT(*) FROM high_comorb) AS high_comorb_admissions,
  (SELECT APPROX_QUANTILES(elix_score, 100)[OFFSET(50)] FROM high_comorb) AS median_risk_score,
  (SELECT (APPROX_QUANTILES(elix_score, 100)[OFFSET(75)] - APPROX_QUANTILES(elix_score, 100)[OFFSET(25)]) FROM high_comorb) AS iqr_risk,
  (SELECT AVG(CAST(death_within_90_days AS FLOAT64)) * 100 FROM death_90) AS ninety_day_mortality_pct,
  (SELECT AVG(CAST(major_comp_flag AS FLOAT64)) * 100 FROM general_major_comp) AS major_comp_rate_general,
  (SELECT median_survivor_los FROM general_survivor_los) AS general_survivor_los_median,
  (SELECT APPROX_QUANTILES(LOS_days_all, 100)[OFFSET(50)] FROM general_cohort WHERE deathtime IS NULL) AS survivor_los_cohort_median,
  (SELECT percentile FROM percentile_of_case) AS case_risk_percentile;