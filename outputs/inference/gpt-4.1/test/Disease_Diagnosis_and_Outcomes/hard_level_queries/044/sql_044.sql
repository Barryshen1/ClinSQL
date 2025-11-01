WITH
-- 1. Female inpatients aged 59-69
female_59_69 AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.gender,
    p.anchor_age,
    p.dod
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),

-- 2. Cardiac arrest admissions (ICD-9: 427.5, ICD-10: I46.x)
cardiac_arrest_admissions AS (
  SELECT DISTINCT
    f.*
  FROM female_59_69 f
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON f.hadm_id = d.hadm_id
  WHERE
    (d.icd_version = 9 AND d.icd_code = '4275')
    OR
    (d.icd_version = 10 AND (d.icd_code LIKE 'I46%' OR d.icd_code LIKE 'I460%' OR d.icd_code LIKE 'I461%' OR d.icd_code LIKE 'I462%' OR d.icd_code LIKE 'I469%'))
),

-- 3. Composite risk score: count of unique comorbidities (ICD codes) per admission
composite_score AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.deathtime,
    ca.dod,
    COUNT(DISTINCT d.icd_code) AS risk_score
  FROM cardiac_arrest_admissions ca
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON ca.hadm_id = d.hadm_id
  GROUP BY ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, ca.deathtime, ca.dod
),

-- 4. Assign quartiles
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM composite_score
),

-- 5. Identify 30-day mortality
mortality AS (
  SELECT
    q.*,
    -- Death within 30 days of admission
    CASE
      WHEN q.deathtime IS NOT NULL AND TIMESTAMP_DIFF(q.deathtime, q.admittime, DAY) <= 30 THEN 1
      WHEN q.dod IS NOT NULL AND TIMESTAMP_DIFF(q.dod, q.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END AS died_30d,
    TIMESTAMP_DIFF(q.dischtime, q.admittime, DAY) AS los_days
  FROM quartiled q
),

-- 6. Cardiovascular and neurologic complications (ICD codes during admission)
complications AS (
  SELECT
    m.hadm_id,
    MAX(CASE
      -- Cardiovascular: stroke (ICD-9: 434.x, 436; ICD-10: I63.x, I64), MI (ICD-9: 410.x; ICD-10: I21.x), arrhythmia (ICD-9: 427.x; ICD-10: I47.x-I49.x)
      WHEN (d.icd_version = 9 AND (
        d.icd_code LIKE '434%' OR d.icd_code = '436' OR d.icd_code LIKE '410%' OR d.icd_code LIKE '427%'
      ))
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'I63%' OR d.icd_code = 'I64' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I47%' OR d.icd_code LIKE 'I48%' OR d.icd_code LIKE 'I49%'
      )) THEN 1 ELSE 0 END) AS cv_complication,
    MAX(CASE
      -- Neurologic: stroke (same as above), seizure (ICD-9: 345.x; ICD-10: G40.x), anoxic brain injury (ICD-9: 348.1; ICD-10: G93.1)
      WHEN (d.icd_version = 9 AND (
        d.icd_code LIKE '434%' OR d.icd_code = '436' OR d.icd_code LIKE '345%' OR d.icd_code = '3481'
      ))
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'I63%' OR d.icd_code = 'I64' OR d.icd_code LIKE 'G40%' OR d.icd_code = 'G931'
      )) THEN 1 ELSE 0 END) AS neuro_complication
  FROM mortality m
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON m.hadm_id = d.hadm_id
  GROUP BY m.hadm_id
),

-- 7. Merge complications with mortality
final AS (
  SELECT
    m.*,
    c.cv_complication,
    c.neuro_complication
  FROM mortality m
  LEFT JOIN complications c
    ON m.hadm_id = c.hadm_id
)

-- 8. Baseline 30-day mortality for all female 59-69 inpatients
, baseline_mortality AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(CASE
      WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1
      WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 30 THEN 1
      ELSE 0
    END) AS deaths_30d
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
)

-- 9. Final report per quartile
SELECT
  risk_quartile,
  COUNT(*) AS n_admissions,
  ROUND(SUM(died_30d) / COUNT(*), 3) AS mortality_30d_rate,
  ROUND(SUM(IFNULL(cv_complication,0)) / COUNT(*), 3) AS cv_complication_rate,
  ROUND(SUM(IFNULL(neuro_complication,0)) / COUNT(*), 3) AS neuro_complication_rate,
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 1) AS median_survivor_los_days
FROM final
WHERE died_30d = 0 -- For median LOS, survivors only
GROUP BY risk_quartile

UNION ALL

SELECT
  NULL AS risk_quartile,
  total_admissions AS n_admissions,
  ROUND(deaths_30d / total_admissions, 3) AS mortality_30d_rate,
  NULL AS cv_complication_rate,
  NULL AS neuro_complication_rate,
  NULL AS median_survivor_los_days
FROM baseline_mortality
ORDER BY risk_quartile;