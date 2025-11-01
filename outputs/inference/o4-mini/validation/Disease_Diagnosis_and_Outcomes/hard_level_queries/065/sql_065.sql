WITH
-- 1. DVT ICD codes
dvt_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%deep vein thromb%'
),

-- 2. DVT cohort: male, age 71-81
dvt_cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code IN (SELECT icd_code FROM dvt_codes)
    )
),

-- 3. Risk score = count of distinct ICDs
dvt_scores AS (
  SELECT c.hadm_id, COUNT(DISTINCT d.icd_code) AS risk_score
  FROM dvt_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON c.hadm_id = d.hadm_id
  GROUP BY c.hadm_id
),

-- 4. 75th percentile threshold
risk_p75 AS (
  SELECT APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS p75
  FROM dvt_scores
),

-- 5. High‐comorbidity DVT
high_comorbidity_dvt AS (
  SELECT s.*
  FROM dvt_scores s
  CROSS JOIN risk_p75
  WHERE s.risk_score >= p75
),

-- 6. 90‐day mortality
dvt_mortality AS (
  SELECT
    h.hadm_id,
    h.risk_score,
    CASE
      WHEN p.dod IS NOT NULL
        AND DATE_DIFF(DATE(p.dod), DATE(a.dischtime), DAY) BETWEEN 0 AND 90
      THEN 1 ELSE 0
    END AS died90
  FROM high_comorbidity_dvt h
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON h.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

-- 7. Major complication codes (example list)
major_comp_codes AS (
  SELECT 'I21' AS icd_code UNION ALL
  SELECT 'I60' UNION ALL
  SELECT 'J96'
),

-- 8. DVT cohort complications & LOS
dvt_comp AS (
  SELECT
    m.hadm_id,
    m.risk_score,
    m.died90,
    MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM major_comp_codes) THEN 1 ELSE 0 END) AS has_comp,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    a.hospital_expire_flag
  FROM dvt_mortality m
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON m.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON m.hadm_id = d.hadm_id
  GROUP BY m.hadm_id, m.risk_score, m.died90, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- 9. General inpatients for comparison
all_adm AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM major_comp_codes) THEN 1 ELSE 0 END) AS has_comp,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- 10. Survivor LOS median for all inpatients
all_los_p50 AS (
  SELECT APPROX_QUANTILES(
           CASE WHEN hospital_expire_flag = 0 THEN los END,
           2
         )[OFFSET(1)] AS p50_los
  FROM all_adm
)

-- Final combined report
SELECT
  'High‐comorbidity DVT'       AS cohort,
  -- risk score median & IQR
  APPROX_QUANTILES(risk_score, 2)[OFFSET(1)]               AS median_risk,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(1)]               AS iqr_lower,
  APPROX_QUANTILES(risk_score, 4)[OFFSET(3)]               AS iqr_upper,
  -- 90-day mortality & complications
  ROUND(100 * AVG(died90), 1)                              AS pct_90d_mortality,
  ROUND(100 * AVG(has_comp), 1)                            AS pct_major_comp,
  -- survivor LOS
  APPROX_QUANTILES(
    CASE WHEN hospital_expire_flag = 0 THEN los END, 2
  )[OFFSET(1)]                                              AS median_los_surv,
  -- index‐patient percentile
  (
    SELECT
      ROUND(
        100 * COUNTIF(ds.risk_score <= idx.idx_score) / COUNT(*)
      , 1)
    FROM dvt_scores AS ds
    CROSS JOIN (
      SELECT risk_score AS idx_score
      FROM high_comorbidity_dvt
      WHERE hadm_id = 123456    -- ← replace with real hadm_id
    ) AS idx
  )                                                         AS index_pct
FROM dvt_comp

UNION ALL

SELECT
  'All inpatients'            AS cohort,
  NULL                         AS median_risk,
  NULL                         AS iqr_lower,
  NULL                         AS iqr_upper,
  NULL                         AS pct_90d_mortality,
  ROUND(100 * AVG(has_comp), 1) AS pct_major_comp,
  all_l.p50_los                AS median_los_surv,
  NULL                         AS index_pct
FROM all_adm, all_los_p50 AS all_l;