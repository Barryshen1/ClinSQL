WITH cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Count distinct diagnoses as a simple risk score proxy
    COUNT(DISTINCT di.icd_code) AS risk_score,
    NTILE(4) OVER (ORDER BY COUNT(DISTINCT di.icd_code)) AS risk_quartile
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx 
      WHERE dx.hadm_id = a.hadm_id 
      AND dx.icd_code = 'J44.1' 
      AND dx.icd_version = 10
    )
  GROUP BY p.subject_id, p.gender, p.anchor_age, p.dod, a.hadm_id, a.admittime, a.dischtime
),

complications AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_admission,
    -- Mechanical ventilation: use procedure codes
    MAX(CASE WHEN pi.icd_code IN ('5A1955Z', '5A09357', '5A09457', '5A09557') THEN 1 ELSE 0 END) AS mechanical_ventilation,
    -- Respiratory failure: use diagnosis codes
    MAX(CASE WHEN rf.icd_code IN ('J96.00', 'J96.01', 'J96.02', 'J96.20', 'J96.21', 'J96.22') THEN 1 ELSE 0 END) AS respiratory_failure
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON c.hadm_id = pi.hadm_id AND pi.icd_version = 10
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` rf
    ON c.hadm_id = rf.hadm_id AND rf.icd_version = 10
  GROUP BY c.hadm_id
),

cohort_with_outcomes AS (
  SELECT
    c.*,
    CASE WHEN c.dod IS NOT NULL AND DATE_DIFF(c.dod, c.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90day,
    CASE WHEN c.dod IS NULL OR DATE_DIFF(c.dod, c.admittime, DAY) > 90 THEN 1 ELSE 0 END AS survived_90day,
    CASE WHEN comp.icu_admission = 1 OR comp.mechanical_ventilation = 1 OR comp.respiratory_failure = 1 THEN 1 ELSE 0 END AS major_complication,
    DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort c
  LEFT JOIN complications comp
    ON c.hadm_id = comp.hadm_id
),

survivor_los AS (
  SELECT
    risk_quartile,
    APPROX_QUANTILE(los_days, 0.5) AS median_los_survivors
  FROM cohort_with_outcomes
  WHERE survived_90day = 1
  GROUP BY risk_quartile
),

broader_mortality AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1 ELSE 0 END) AS deaths_90day,
    ROUND(100.0 * SUM(CASE WHEN p.dod IS NOT NULL AND DATE_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_rate_percent
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
)

SELECT
  c.risk_quartile,
  COUNT(*) AS n_patients,
  ROUND(100.0 * SUM(mortality_90day) / COUNT(*), 2) AS mortality_90day_percent,
  ROUND(100.0 * SUM(major_complication) / COUNT(*), 2) AS major_complication_percent,
  s.median_los_survivors
FROM cohort_with_outcomes c
LEFT JOIN survivor_los s
  ON c.risk_quartile = s.risk_quartile
GROUP BY c.risk_quartile, s.median_los_survivors
ORDER BY c.risk_quartile;

-- Additionally, output the broader mortality for context
SELECT * FROM broader_mortality;