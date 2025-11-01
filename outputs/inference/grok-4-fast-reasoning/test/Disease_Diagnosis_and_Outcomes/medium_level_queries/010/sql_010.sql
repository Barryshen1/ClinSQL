WITH comorb AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE '250%' THEN 1 ELSE 0 END) AS has_dm,
    MAX(CASE WHEN icd_code LIKE 'N18%' OR icd_code LIKE '585%' OR icd_code = '586' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN icd_code LIKE 'I50%' OR icd_code LIKE '428%' THEN 1 ELSE 0 END) AS has_hf,
    MAX(CASE WHEN icd_code = 'I10' OR icd_code LIKE 'I11%' OR icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'I15%' 
             OR icd_code LIKE '401%' OR icd_code LIKE '402%' OR icd_code LIKE '403%' OR icd_code LIKE '404%' OR icd_code LIKE '405%' 
             THEN 1 ELSE 0 END) AS has_htn
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag,
    SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) AS age,
    COALESCE(c.has_dm, 0) AS has_dm,
    COALESCE(c.has_ckd, 0) AS has_ckd,
    COALESCE(c.has_hf, 0) AS has_hf,
    COALESCE(c.has_htn, 0) AS has_htn,
    COALESCE(c.has_dm, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_hf, 0) + COALESCE(c.has_htn, 0) AS comorb_count,
    CASE 
      WHEN COALESCE(c.has_dm, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_hf, 0) + COALESCE(c.has_htn, 0) <= 1 THEN 'low'
      WHEN COALESCE(c.has_dm, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_hf, 0) + COALESCE(c.has_htn, 0) = 2 THEN 'med'
      ELSE 'high'
    END AS comorb_level
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN comorb c ON a.hadm_id = c.hadm_id
  WHERE p.gender = 'M'
    AND SAFE_CAST(p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS INT64) BETWEEN 78 AND 88
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
        AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE '410%')
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` ex 
      WHERE ex.hadm_id = a.hadm_id 
        AND (
          ex.icd_code = 'I214' OR ex.icd_code LIKE 'R570%' OR ex.icd_code = '78551' OR
          ex.icd_code LIKE 'J96%' OR ex.icd_code IN ('51881', '51882', '51884')
        )
    )
),
cohort_with_quart AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM cohort
),
summary AS (
  SELECT 
    los_quartile,
    comorb_level,
    COUNT(*) AS n_total,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(CAST(has_ckd AS FLOAT64)) * 100 AS ckd_prevalence,
    AVG(CAST(has_dm AS FLOAT64)) * 100 AS diabetes_prevalence
  FROM cohort_with_quart
  GROUP BY los_quartile, comorb_level
)
SELECT 
  los_quartile,
  comorb_level,
  n_total,
  n_deaths,
  CAST(n_deaths AS FLOAT64) / n_total AS mortality_rate,
  CAST(n_deaths AS FLOAT64) / n_total - 1.96 * SQRT(
    (CAST(n_deaths AS FLOAT64) / n_total) * (1 - CAST(n_deaths AS FLOAT64) / n_total) / n_total
  ) AS ci_lower,
  CAST(n_deaths AS FLOAT64) / n_total + 1.96 * SQRT(
    (CAST(n_deaths AS FLOAT64) / n_total) * (1 - CAST(n_deaths AS FLOAT64) / n_total) / n_total
  ) AS ci_upper,
  ckd_prevalence,
  diabetes_prevalence
FROM summary
ORDER BY los_quartile, comorb_level;