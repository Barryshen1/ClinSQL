WITH ugib_icd_codes AS (
  -- List of ICD codes for upper GI bleeding (ICD-9 and ICD-10)
  SELECT 'K92.0' AS icd_code UNION ALL
  SELECT 'K92.1' UNION ALL
  SELECT 'K92.2' UNION ALL
  SELECT 'I85.01' UNION ALL
  SELECT 'K25' UNION ALL
  SELECT 'K25.0' UNION ALL
  SELECT 'K25.2' UNION ALL
  SELECT 'K25.4' UNION ALL
  SELECT 'K25.6' UNION ALL
  SELECT 'K26' UNION ALL
  SELECT 'K26.0' UNION ALL
  SELECT 'K26.2' UNION ALL
  SELECT 'K26.4' UNION ALL
  SELECT 'K26.6' UNION ALL
  SELECT 'K27' UNION ALL
  SELECT 'K27.0' UNION ALL
  SELECT 'K27.2' UNION ALL
  SELECT 'K27.4' UNION ALL
  SELECT 'K27.6' UNION ALL
  SELECT 'K28' UNION ALL
  SELECT 'K28.0' UNION ALL
  SELECT 'K28.2' UNION ALL
  SELECT 'K28.4' UNION ALL
  SELECT 'K28.6' UNION ALL
  SELECT '578.0' UNION ALL
  SELECT '578.1' UNION ALL
  SELECT '578.9'
),
major_complication_icd_codes AS (
  -- List of ICD codes for major complications
  SELECT 'R57' AS icd_code UNION ALL -- Shock
  SELECT 'R57.0' UNION ALL
  SELECT 'R57.1' UNION ALL
  SELECT 'R57.2' UNION ALL
  SELECT 'N17' UNION ALL -- Acute renal failure
  SELECT 'N17.0' UNION ALL
  SELECT 'N17.1' UNION ALL
  SELECT 'N17.2' UNION ALL
  SELECT 'N17.8' UNION ALL
  SELECT 'N17.9' UNION ALL
  SELECT 'A41' UNION ALL -- Sepsis
  SELECT 'A41.0' UNION ALL
  SELECT 'A41.9' UNION ALL
  SELECT 'I46' UNION ALL -- Cardiac arrest
  SELECT 'I46.0' UNION ALL
  SELECT 'I46.9' UNION ALL
  SELECT 'J96' UNION ALL -- Respiratory failure
  SELECT 'J96.0' UNION ALL
  SELECT 'J96.9' UNION ALL
  SELECT 'D65' -- DIC
),
ugib_admissions AS (
  -- Admissions with upper GI bleeding diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN ugib_icd_codes u
    ON (d.icd_code = u.icd_code OR STARTS_WITH(d.icd_code, u.icd_code))
),
major_complications AS (
  -- Admissions with major complication diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN major_complication_icd_codes m
    ON (d.icd_code = m.icd_code OR STARTS_WITH(d.icd_code, m.icd_code))
),
cohort AS (
  -- Cohort: male inpatients aged 64–74 with UGIB
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN ugib_admissions u
    ON a.subject_id = u.subject_id AND a.hadm_id = u.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diagnosis_counts AS (
  -- Diagnosis count per admission
  SELECT
    subject_id,
    hadm_id,
    COUNT(*) AS diagnosis_count
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  GROUP BY subject_id, hadm_id
),
cohort_with_scores AS (
  -- Add diagnosis count and major complication flag
  SELECT
    c.*,
    COALESCE(dc.diagnosis_count, 0) AS diagnosis_count,
    CASE WHEN mc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS major_complication,
    COALESCE(dc.diagnosis_count, 0) + 20 * CASE WHEN mc.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS composite_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) AS los,
    -- 30-day mortality: died within 30 days of admittime
    CASE
      WHEN c.deathtime IS NOT NULL AND TIMESTAMP_DIFF(c.deathtime, c.admittime, DAY) <= 30 THEN 1
      WHEN c.dod IS NOT NULL AND TIMESTAMP_DIFF(c.dod, c.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS mortality_30d
  FROM cohort c
  LEFT JOIN diagnosis_counts dc
    ON c.subject_id = dc.subject_id AND c.hadm_id = dc.hadm_id
  LEFT JOIN major_complications mc
    ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
),
cohort_with_quintile AS (
  -- Assign quintiles by composite risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY composite_score) AS quintile
  FROM cohort_with_scores
),
summary AS (
  -- Aggregate per quintile
  SELECT
    quintile,
    COUNT(*) AS n,
    ROUND(AVG(composite_score), 2) AS mean_score,
    ROUND(100.0 * SUM(mortality_30d) / COUNT(*), 2) AS mortality_30d_pct,
    ROUND(100.0 * SUM(major_complication) / COUNT(*), 2) AS major_complication_pct,
    -- Median LOS among survivors (mortality_30d = 0)
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los_survivors
  FROM cohort_with_quintile
  WHERE mortality_30d = 0
  GROUP BY quintile
  ORDER BY quintile
),
individual_69yo AS (
  -- For a 69-year-old male inpatient, show his quintile and score
  SELECT
    subject_id,
    hadm_id,
    composite_score,
    quintile
  FROM cohort_with_quintile
  WHERE anchor_age = 69
  LIMIT 1
)
SELECT
  s.*,
  i.subject_id AS example_subject_id,
  i.hadm_id AS example_hadm_id,
  i.composite_score AS example_composite_score,
  i.quintile AS example_quintile
FROM summary s
LEFT JOIN individual_69yo i
  ON s.quintile = i.quintile
ORDER BY s.quintile;