WITH 
-- Base admissions enriched with patient demographics and diagnosis counts
admissions_dx AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    COUNT(DISTINCT d.icd_code) AS diagnosis_count,
    -- flag for any septic shock diagnosis
    MAX(CASE WHEN LOWER(dic.long_title) LIKE '%septic shock%' THEN 1 ELSE 0 END) AS has_septic_shock,
    -- flag for any major complication diagnosis
    MAX(CASE WHEN LOWER(dic.long_title) LIKE '%complication%' THEN 1 ELSE 0 END) AS has_complication,
    -- 90-day mortality flag
    CASE 
      WHEN p.dod IS NOT NULL 
           AND DATE_DIFF(p.dod, a.dischtime, DAY) BETWEEN 0 AND 90 
      THEN 1 ELSE 0 END AS died_within_90d,
    -- survival to discharge flag
    CASE WHEN a.hospital_expire_flag = 0 THEN 1 ELSE 0 END AS survived_to_discharge,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON d.icd_code = dic.icd_code 
    AND d.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
  GROUP BY
    a.subject_id, a.hadm_id, p.gender, p.anchor_age, 
    a.admittime, a.dischtime, a.deathtime, p.dod, a.hospital_expire_flag
),

-- Septic shock cohort: male 63-73, septic shock, >15 diagnoses
shock_cohort AS (
  SELECT
    hadm_id,
    diagnosis_count,
    died_within_90d
  FROM admissions_dx
  WHERE has_septic_shock = 1
    AND diagnosis_count > 15
),

-- General male inpatient cohort age 63-73
general_cohort AS (
  SELECT
    hadm_id,
    diagnosis_count,
    has_complication,
    survived_to_discharge,
    los_days
  FROM admissions_dx
)

-- Final aggregations
SELECT
  'Septic Shock Cohort (M,63-73,>15 dx)' AS cohort,
  NULL AS mean_risk_score,
  ROUND(100 * AVG(died_within_90d), 2) AS pct_90d_mortality,
  NULL AS major_complication_rate,
  NULL AS survivor_los_days,
  NULL AS diagnosis_count_percentile
FROM shock_cohort

UNION ALL

SELECT
  'General Inpatient Cohort (M,63-73)' AS cohort,
  NULL AS mean_risk_score,
  NULL AS pct_90d_mortality,
  ROUND(100 * AVG(has_complication), 2) AS major_complication_rate,
  ROUND(AVG(CASE WHEN survived_to_discharge = 1 THEN los_days END), 2) AS survivor_los_days,
  NULL AS diagnosis_count_percentile
FROM general_cohort

UNION ALL

-- Diagnosis‐count percentile for the specific profile (16 diagnoses)
SELECT
  'Percentile for Profile: dx_count=16' AS cohort,
  NULL AS mean_risk_score,
  NULL AS pct_90d_mortality,
  NULL AS major_complication_rate,
  NULL AS survivor_los_days,
  ARRAY_LENGTH(
    ARRAY(
      SELECT q FROM UNNEST(
        (SELECT APPROX_QUANTILES(diagnosis_count, 100) FROM general_cohort)
      ) AS q
      WHERE q <= 16
    )
  ) AS diagnosis_count_percentile
;