WITH
-- Admissions with an upper GI bleeding diagnosis (keyword-based)
uppergi_admissions AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE (
    LOWER(COALESCE(dd.long_title,'')) LIKE '%hematemesis%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%melena%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%gastrointestinal hemorrhag%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%upper gastrointestinal%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%peptic ulcer with hemorrhage%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%esophageal varices with bleeding%'
    OR LOWER(COALESCE(dd.long_title,'')) LIKE '%upper gi bleed%'
  )
),

-- Pre-aggregate diagnoses per admission to avoid correlated subqueries
diagnoses_agg AS (
  SELECT
    di.hadm_id,
    COUNT(DISTINCT di.icd_code) AS diagnosis_count,
    MAX(
      CASE
        WHEN (
             LOWER(COALESCE(dd.long_title,'')) LIKE '%sepsis%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%septicemia%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%septic shock%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%shock%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%acute renal failure%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%acute kidney failure%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%renal failure%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%acute respiratory failure%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%respiratory failure%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%cardiac arrest%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%myocardial infarction%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%infarction%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%stroke%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%cerebrovascular%'
          OR LOWER(COALESCE(dd.long_title,'')) LIKE '%pulmonary embol%'
        )
        THEN 1 ELSE 0
      END
    ) AS major_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE di.hadm_id IN (SELECT hadm_id FROM uppergi_admissions)
  GROUP BY di.hadm_id
),

-- Compute per-admission metrics by joining aggregated diagnoses
admission_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod AS patient_dod,
    COALESCE(da.diagnosis_count, 0) AS diagnosis_count,
    COALESCE(da.major_complication, 0) AS major_complication,
    -- LOS in fractional days
    CASE
      WHEN a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
      THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0
      ELSE NULL
    END AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN diagnoses_agg da
    ON a.hadm_id = da.hadm_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM uppergi_admissions)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),

-- Add composite score and assign quintiles
scored_quintiles AS (
  SELECT
    *,
    (diagnosis_count + 20 * major_complication) AS composite_score,
    NTILE(5) OVER (ORDER BY (diagnosis_count + 20 * major_complication) ASC) AS quintile
  FROM admission_scores
)

-- Final aggregation per quintile
SELECT
  quintile,
  COUNT(*) AS n_admissions,
  ROUND(AVG(composite_score), 2) AS mean_composite_score,
  ROUND(
    100.0 * SUM(
      CASE
        WHEN patient_dod IS NOT NULL
         AND DATE_DIFF(patient_dod, DATE(admittime), DAY) BETWEEN 0 AND 30
        THEN 1 ELSE 0
      END
    ) / NULLIF(COUNT(*), 0)
  , 2) AS pct_30d_mortality,
  ROUND(100.0 * SUM(major_complication) / NULLIF(COUNT(*), 0), 2) AS pct_major_complication,
  -- median LOS among hospital survivors (hospital_expire_flag = 0)
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, los_days, NULL), 2)[OFFSET(1)] AS median_los_survivors_days
FROM scored_quintiles
GROUP BY quintile
ORDER BY quintile;