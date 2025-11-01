WITH
-- Base cohort: males 88-98 with pneumonia and ICU stay
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    CASE WHEN a.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) ELSE NULL END AS survival_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '486%') OR  -- ICD-9 pneumonia
      (d.icd_version = 10 AND d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR
       d.icd_code LIKE 'J14%' OR d.icd_code LIKE 'J15%' OR
       d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%' OR d.icd_code LIKE 'J18%')
    )
),

-- Calculate OASIS-like risk score components
risk_factors AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    -- Comorbidities (simplified for example)
    MAX(CASE WHEN d.icd_code IN ('428', 'I50') THEN 1 ELSE 0 END) AS has_chf,
    MAX(CASE WHEN d.icd_code IN ('414', 'I25') THEN 1 ELSE 0 END) AS has_cad,
    MAX(CASE WHEN d.icd_code IN ('496', 'J44') THEN 1 ELSE 0 END) AS has_copd,
    -- Vital signs (first 24 hours in ICU)
    AVG(CASE WHEN ce.itemid IN (220210, 220277) THEN ce.valuenum ELSE NULL END) AS resp_rate,
    AVG(CASE WHEN ce.itemid IN (220223, 220278) THEN ce.valuenum ELSE NULL END) AS spo2,
    -- Lab values (first 24 hours in ICU)
    AVG(CASE WHEN le.itemid = 50912 THEN le.valuenum ELSE NULL END) AS bun,
    AVG(CASE WHEN le.itemid = 50983 THEN le.valuenum ELSE NULL END) AS sodium
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON c.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.hadm_id = ce.hadm_id
    AND ce.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id, c.anchor_age
),

-- Calculate composite risk score (simplified OASIS-like score)
risk_scores AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age,
    -- Simplified risk score calculation (0-100 scale)
    ROUND(
      10 * anchor_age/100 +
      20 * has_chf +
      20 * has_cad +
      15 * has_copd +
      10 * (resp_rate - 20)/10 +
      10 * (100 - spo2)/10 +
      10 * (bun - 20)/10 +
      5 * (sodium - 140)/5,
      0
    ) AS risk_score
  FROM risk_factors
),

-- Identify outcomes
outcomes AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.hospital_expire_flag,
    c.survival_days,
    -- AKI (ICD or lab criteria)
    MAX(CASE WHEN
      (d1.icd_version = 9 AND d1.icd_code LIKE '584%') OR
      (d1.icd_version = 10 AND d1.icd_code LIKE 'N17%') OR
      (d1.icd_version = 10 AND d1.icd_code LIKE 'N18%') OR
      (d1.icd_version = 10 AND d1.icd_code LIKE 'N19%')
    THEN 1 ELSE 0 END) AS has_aki,
    -- ARDS (ICD or Berlin criteria)
    MAX(CASE WHEN
      (d2.icd_version = 9 AND d2.icd_code = '518.82') OR
      (d2.icd_version = 10 AND d2.icd_code = 'J80')
    THEN 1 ELSE 0 END) AS has_ards
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON c.hadm_id = d1.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON c.hadm_id = d2.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.hospital_expire_flag, c.survival_days
)

-- Final results
SELECT
  COUNT(DISTINCT r.subject_id) AS cohort_size,
  -- Risk score distribution
  MIN(r.risk_score) AS risk_score_min,
  APPROX_QUANTILES(r.risk_score, 4)[OFFSET(1)] AS risk_score_q1,
  APPROX_QUANTILES(r.risk_score, 2)[OFFSET(1)] AS risk_score_median,
  APPROX_QUANTILES(r.risk_score, 4)[OFFSET(3)] AS risk_score_q3,
  MAX(r.risk_score) AS risk_score_max,
  -- Outcomes
  ROUND(100 * SUM(o.hospital_expire_flag) / COUNT(DISTINCT r.subject_id), 1) AS mortality_rate_pct,
  ROUND(100 * SUM(o.has_aki) / COUNT(DISTINCT r.subject_id), 1) AS aki_rate_pct,
  ROUND(100 * SUM(o.has_ards) / COUNT(DISTINCT r.subject_id), 1) AS ards_rate_pct,
  APPROX_QUANTILES(o.survival_days, 2)[OFFSET(1)] AS median_survival_days
FROM risk_scores r
JOIN outcomes o ON r.subject_id = o.subject_id AND r.hadm_id = o.hadm_id;