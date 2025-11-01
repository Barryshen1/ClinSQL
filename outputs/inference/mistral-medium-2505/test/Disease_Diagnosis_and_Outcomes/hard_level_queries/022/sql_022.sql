WITH
-- Define AKI and ARDS ICD codes
icd_codes AS (
  SELECT
    'N17' AS icd_code, 'AKI' AS condition UNION ALL
    SELECT 'N17.0', 'AKI' UNION ALL
    SELECT 'N17.1', 'AKI' UNION ALL
    SELECT 'N17.2', 'AKI' UNION ALL
    SELECT 'N17.8', 'AKI' UNION ALL
    SELECT 'N17.9', 'AKI' UNION ALL
    SELECT 'J80', 'ARDS' UNION ALL
    SELECT 'J80.0', 'ARDS'
),

-- Get female patients aged 40-50
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- Get admissions with AKI diagnosis
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP(a.admittime) AS admittime,
    TIMESTAMP(a.dischtime) AS dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    icd_codes c
    ON d.icd_code = c.icd_code AND c.condition = 'AKI'
  WHERE
    a.hospital_expire_flag = 0  -- Exclude in-hospital deaths
),

-- Get all diagnoses for these patients (excluding AKI)
comorbidities AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count,
    MAX(CASE WHEN c.condition = 'ARDS' THEN 1 ELSE 0 END) AS has_ards
  FROM
    aki_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    icd_codes c
    ON d.icd_code = c.icd_code
  WHERE
    c.condition != 'AKI'  -- Exclude AKI from comorbidity count
  GROUP BY
    a.subject_id, a.hadm_id
),

-- Calculate composite risk score
risk_scores AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP(p.dod) AS dod,
    c.comorbidity_count,
    c.has_ards,
    (5 * c.comorbidity_count) + (50 * c.has_ards) AS composite_risk_score
  FROM
    aki_admissions a
  JOIN
    eligible_patients p
    ON a.subject_id = p.subject_id
  JOIN
    comorbidities c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
),

-- Calculate 30-day post-discharge mortality
mortality AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN dod IS NOT NULL
      AND TIMESTAMP_DIFF(dod, dischtime, DAY) BETWEEN 1 AND 30
      THEN 1
      ELSE 0
    END AS died_within_30_days
  FROM
    risk_scores
),

-- Combine all data with quintiles
final_data AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.composite_risk_score,
    m.died_within_30_days,
    c.has_ards,
    TIMESTAMP_DIFF(r.dischtime, r.admittime, DAY) AS los_days,
    NTILE(5) OVER (ORDER BY r.composite_risk_score) AS risk_quintile
  FROM
    risk_scores r
  JOIN
    mortality m
    ON r.subject_id = m.subject_id AND r.hadm_id = m.hadm_id
  JOIN
    comorbidities c
    ON r.subject_id = c.subject_id AND r.hadm_id = c.hadm_id
),

-- Calculate median LOS for survivors by quintile
quintile_stats AS (
  SELECT
    risk_quintile,
    PERCENTILE_CONT(CASE WHEN died_within_30_days = 0 THEN los_days ELSE NULL END, 0.5)
      OVER (PARTITION BY risk_quintile) AS median_los_survivors
  FROM
    final_data
)

-- Final aggregation by quintile
SELECT
  f.risk_quintile,
  COUNT(*) AS n,
  ROUND(100 * AVG(f.died_within_30_days), 1) AS mortality_30day_percent,
  ROUND(100 * AVG(f.has_ards), 1) AS ards_cooccurrence_percent,
  ROUND(q.median_los_survivors, 1) AS median_los_survivors
FROM
  final_data f
JOIN
  quintile_stats q
  ON f.risk_quintile = q.risk_quintile
GROUP BY
  f.risk_quintile, q.median_los_survivors
ORDER BY
  f.risk_quintile;