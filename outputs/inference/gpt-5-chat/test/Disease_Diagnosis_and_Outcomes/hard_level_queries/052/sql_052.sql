WITH copd_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code IN ('J441','J440'))
    OR (icd_version = 9 AND (icd_code LIKE '4912%' OR icd_code = '496'))
),
-- Identify complications
complication_dx AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    -- Sepsis
    (icd_version = 10 AND icd_code LIKE 'A41%')
    OR (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code LIKE '9959%'))
    -- Acute kidney failure
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
    OR (icd_version = 9 AND icd_code LIKE '584%')
    -- Acute respiratory failure
    OR (icd_version = 10 AND icd_code LIKE 'J96%')
    OR (icd_version = 9 AND icd_code LIKE '51881')
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    -- compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admittime,
    a.dischtime,
    p.dod,
    -- Simple proxy risk score = age_at_admit (placeholder)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS risk_score,
    -- LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN copd_dx cd
    ON a.hadm_id = cd.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 75 AND 85
),
cohort_with_flags AS (
  SELECT
    c.*,
    CASE 
      WHEN c.dod IS NOT NULL 
           AND c.dod BETWEEN c.admittime AND c.admittime + INTERVAL 90 DAY
      THEN 1 ELSE 0 END AS mortality_90d,
    CASE WHEN comp.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_complication
  FROM cohort c
  LEFT JOIN complication_dx comp
    ON c.hadm_id = comp.hadm_id
),
cohort_with_quartiles AS (
  SELECT *,
         NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM cohort_with_flags
),
quartile_stats AS (
  SELECT
    risk_quartile,
    COUNT(*) AS n,
    AVG(mortality_90d)*100 AS mortality_90d_pct,
    AVG(major_complication)*100 AS major_complication_pct,
    -- Median survivor LOS
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los_days
  FROM cohort_with_quartiles
  WHERE mortality_90d = 0  -- survivors only for median LOS
  GROUP BY risk_quartile
),
overall_stats AS (
  SELECT
    AVG(mortality_90d)*100 AS overall_mortality_90d_pct
  FROM cohort_with_flags
)
SELECT
  q.risk_quartile,
  q.n,
  q.mortality_90d_pct,
  q.major_complication_pct,
  q.median_survivor_los_days,
  o.overall_mortality_90d_pct
FROM quartile_stats q
CROSS JOIN overall_stats o
ORDER BY q.risk_quartile;