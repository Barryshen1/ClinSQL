WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  -- Filter for AMI diagnosis
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = a.hadm_id
      AND (
        (d.icd_version = 9 AND d.icd_code LIKE '410%') 
        OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      )
  )
  -- Ensure ICU stay
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    WHERE i.hadm_id = a.hadm_id
  )
  -- Apply age and gender filters
  AND p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
),

cohort_outcomes AS (
  SELECT
    c.*,
    -- 30-day mortality flag (in-hospital death within 30 days)
    CASE 
      WHEN c.deathtime IS NOT NULL 
        AND DATE_DIFF(c.deathtime, c.admittime, DAY) <= 30 
        THEN 1 
      ELSE 0 
    END AS mortality_30d,
    -- AKI diagnosis flag
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '584%')
            OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          )
      ) THEN 1
      ELSE 0
    END AS aki_flag,
    -- ARDS diagnosis flag
    CASE 
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        WHERE d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 9 AND d.icd_code = '518.82')
            OR (d.icd_version = 10 AND d.icd_code = 'J80')
          )
      ) THEN 1
      ELSE 0
    END AS ards_flag,
    -- Survival days (for decedents only)
    CASE 
      WHEN c.deathtime IS NOT NULL 
        THEN DATE_DIFF(c.deathtime, c.admittime, DAY) 
      ELSE NULL 
    END AS survival_days
  FROM cohort c
)

SELECT
  -- Composite risk percentile (undefined in MIMIC)
  NULL AS avg_composite_risk_percentile,
  -- 30-day mortality rate (%)
  ROUND(AVG(mortality_30d) * 100, 2) AS mortality_30d_rate_pct,
  -- AKI rate (%)
  ROUND(AVG(aki_flag) * 100, 2) AS aki_rate_pct,
  -- ARDS rate (%)
  ROUND(AVG(ards_flag) * 100, 2) AS ards_rate_pct,
  -- Median survival of decedents (days)
  APPROX_QUANTILES(survival_days, 2 IGNORE NULLS)[OFFSET(1)] AS median_survival_days
FROM cohort_outcomes;