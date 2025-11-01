WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
dm_hf_adms AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
  HAVING COUNT(CASE
    WHEN (icd_version = 9 AND icd_code LIKE '250%')
      OR (icd_version = 10 AND (
        icd_code LIKE 'E10%' OR icd_code LIKE 'E11%'
        OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'
        OR icd_code LIKE 'E14%'
      ))
    THEN 1 END) > 0
    AND COUNT(CASE
    WHEN (icd_version = 9 AND icd_code LIKE '428%')
      OR (icd_version = 10 AND icd_code LIKE 'I50%')
    THEN 1 END) > 0
),
cohort_hadm AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN dm_hf_adms dh ON c.hadm_id = dh.hadm_id
),
med_events AS (
  SELECT e.hadm_id, e.charttime,
    CASE WHEN LOWER(e.medication) LIKE '%insulin%' THEN 1 ELSE 0 END AS is_insulin,
    CASE WHEN LOWER(e.medication) LIKE '%metformin%'
      OR LOWER(e.medication) LIKE '%glipizide%'
      OR LOWER(e.medication) LIKE '%glyburide%'
      OR LOWER(e.medication) LIKE '%glimepiride%'
      OR LOWER(e.medication) LIKE '%pioglitazone%'
      OR LOWER(e.medication) LIKE '%rosiglitazone%'
      OR LOWER(e.medication) LIKE '%sitagliptin%'
      OR LOWER(e.medication) LIKE '%saxagliptin%'
      OR LOWER(e.medication) LIKE '%linagliptin%'
      OR LOWER(e.medication) LIKE '%alogliptin%'
      OR LOWER(e.medication) LIKE '%repaglinide%'
      OR LOWER(e.medication) LIKE '%nateglinide%'
      OR LOWER(e.medication) LIKE '%acarbose%'
      OR LOWER(e.medication) LIKE '%miglitol%'
      OR LOWER(e.medication) LIKE '%empagliflozin%'
      OR LOWER(e.medication) LIKE '%dapagliflozin%'
      OR LOWER(e.medication) LIKE '%canagliflozin%'
      OR LOWER(e.medication) LIKE '%ertugliflozin%'
    THEN 1 ELSE 0 END AS is_oral
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort_hadm ch ON e.hadm_id = ch.hadm_id
),
early_flags AS (
  SELECT ch.hadm_id,
    MAX(CASE WHEN me.is_insulin = 1
      AND me.charttime >= ch.admittime
      AND me.charttime < ch.admittime + INTERVAL 12 HOUR
    THEN 1 ELSE 0 END) AS early_insulin,
    MAX(CASE WHEN me.is_oral = 1
      AND me.charttime >= ch.admittime
      AND me.charttime < ch.admittime + INTERVAL 12 HOUR
    THEN 1 ELSE 0 END) AS early_oral
  FROM cohort_hadm ch
  LEFT JOIN med_events me ON ch.hadm_id = me.hadm_id
  GROUP BY ch.hadm_id
),
late_flags AS (
  SELECT ch.hadm_id,
    MAX(CASE WHEN me.is_insulin = 1
      AND me.charttime >= GREATEST(ch.admittime, ch.dischtime - INTERVAL 72 HOUR)
      AND me.charttime < ch.dischtime
    THEN 1 ELSE 0 END) AS late_insulin,
    MAX(CASE WHEN me.is_oral = 1
      AND me.charttime >= GREATEST(ch.admittime, ch.dischtime - INTERVAL 72 HOUR)
      AND me.charttime < ch.dischtime
    THEN 1 ELSE 0 END) AS late_oral
  FROM cohort_hadm ch
  LEFT JOIN med_events me ON ch.hadm_id = me.hadm_id
  GROUP BY ch.hadm_id
),
flags AS (
  SELECT ef.hadm_id, ef.early_insulin, ef.early_oral, lf.late_insulin, lf.late_oral
  FROM early_flags ef
  INNER JOIN late_flags lf ON ef.hadm_id = lf.hadm_id
),
classified AS (
  SELECT hadm_id,
    CASE
      WHEN early_insulin = 1 THEN 'Insulin'
      WHEN early_oral = 1 THEN 'Oral Agents'
      ELSE 'None'
    END AS early_class,
    CASE
      WHEN late_insulin = 1 THEN 'Insulin'
      WHEN late_oral = 1 THEN 'Oral Agents'
      ELSE 'None'
    END AS late_class
  FROM flags
),
total_n AS (
  SELECT COUNT(*) AS total_admissions FROM classified
),
rates AS (
  SELECT 'Early' AS period, early_class AS class,
    COUNT(*) AS n,
    ROUND(COUNT(*) * 100.0 / tn.total_admissions, 2) AS rate_percent
  FROM classified
  CROSS JOIN total_n tn
  GROUP BY early_class
  UNION ALL
  SELECT 'Late' AS period, late_class AS class,
    COUNT(*) AS n,
    ROUND(COUNT(*) * 100.0 / tn.total_admissions, 2) AS rate_percent
  FROM classified
  CROSS JOIN total_n tn
  GROUP BY late_class
),
transitions AS (
  SELECT early_class, late_class,
    COUNT(*) AS n,
    ROUND(COUNT(*) * 100.0 / tn.total_admissions, 2) AS transition_percent
  FROM classified
  CROSS JOIN total_n tn
  GROUP BY early_class, late_class
)
SELECT 'rates' as section, period as metric1, class as metric2, n, rate_percent as percent
FROM rates
UNION ALL
SELECT 'transitions' as section, early_class as metric1, late_class as metric2, n, transition_percent as percent
FROM transitions
ORDER BY section, metric1, metric2;