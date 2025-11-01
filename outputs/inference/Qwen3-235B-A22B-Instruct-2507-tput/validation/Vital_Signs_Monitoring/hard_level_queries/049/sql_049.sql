WITH sepsis_codes AS (
  SELECT 'A419' AS icd_code, 10 AS icd_version
  UNION ALL SELECT 'R6520', 10
  UNION ALL SELECT 'R6521', 10
  UNION ALL SELECT 'A4151', 10
  UNION ALL SELECT 'A418', 10
  UNION ALL SELECT 'A410', 10
),
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    adm.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN sepsis_codes s
    ON diag.icd_code = s.icd_code AND diag.icd_version = s.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 78 AND 88
),
-- Simulate instability score (placeholder: deterministic function of stay_id)
cohort_with_score AS (
  SELECT
    stay_id,
    icu_los,
    hospital_expire_flag,
    -- Placeholder instability score: simulate a plausible range (e.g., 10-110)
    MOD(stay_id, 100) + 10 AS instability_score
  FROM cohort
),
percentile_calc AS (
  SELECT
    -- Compute percentile rank of score = 85
    PERCENT_RANK() OVER (ORDER BY instability_score) AS pct_rank,
    instability_score
  FROM cohort_with_score
),
target_percentile AS (
  SELECT
    APPROX_QUANTILES(CASE WHEN instability_score <= 85 THEN instability_score END, 1000)[OFFSET(999)] AS score_le_85,
    APPROX_QUANTILES(instability_score, 1000)[OFFSET(999)] AS max_score,
    COUNT(CASE WHEN instability_score <= 85 THEN 1 END) / COUNT(*) AS percentile_rank_of_85
  FROM cohort_with_score
),
quartile_analysis AS (
  SELECT
    instability_score,
    icu_los,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS instability_quartile
  FROM cohort_with_score
),
quartile_4_stats AS (
  SELECT
    AVG(icu_los) AS mean_los_q4,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate_q4
  FROM quartile_analysis
  WHERE instability_quartile = 1  -- NTILE(4) with DESC order: 1 = highest quartile
)
SELECT
  (SELECT percentile_rank_of_85 FROM target_percentile) AS percentile_rank_of_85,
  (SELECT mean_los_q4 FROM quartile_4_stats) AS mean_los_q4,
  (SELECT mortality_rate_q4 FROM quartile_4_stats) AS mortality_rate_q4;