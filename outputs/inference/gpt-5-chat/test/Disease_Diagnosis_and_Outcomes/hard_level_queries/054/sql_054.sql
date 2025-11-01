WITH base AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
),
diag AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    dd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
),
diag_counts AS (
  SELECT
    b.hadm_id,
    -- PE flag
    MAX(CASE WHEN LOWER(long_title) LIKE '%pulmonary embolism%' THEN 1 ELSE 0 END) AS pe_flag,
    -- Cardio complication flag
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(long_title), '(cardiac|heart|myocard|arrhythmia|coronary)') THEN 1 ELSE 0 END) AS cardio_flag,
    -- Neuro complication flag
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(long_title), '(stroke|intracranial|brain|seizure)') THEN 1 ELSE 0 END) AS neuro_flag,
    -- Comorbidity count: number of distinct ICD diagnoses excluding PE
    COUNT(DISTINCT CASE WHEN LOWER(long_title) NOT LIKE '%pulmonary embolism%' THEN long_title END) AS comorbidity_count
  FROM base b
  LEFT JOIN diag d
    ON b.subject_id = d.subject_id
    AND b.hadm_id = d.hadm_id
  GROUP BY b.hadm_id
),
scored AS (
  SELECT
    b.*,
    dc.pe_flag,
    dc.cardio_flag,
    dc.neuro_flag,
    dc.comorbidity_count,
    CASE WHEN b.hospital_expire_flag = 1 
         OR (b.dod IS NOT NULL AND DATETIME_DIFF(b.dod, b.admittime, DAY) <= 30) THEN 1 ELSE 0 END AS mort30_flag
  FROM base b
  LEFT JOIN diag_counts dc
    ON b.hadm_id = dc.hadm_id
),
grp AS (
  SELECT
    *,
    CASE 
      WHEN pe_flag = 1 AND comorbidity_count >= 4 THEN 'PE_high_comorb'
      WHEN pe_flag = 0 THEN 'Control'
      ELSE NULL 
    END AS cohort
  FROM scored
)
SELECT
  cohort,
  COUNT(*) AS n_adm,
  ROUND(AVG(comorbidity_count),2) AS mean_comorbidity_score,
  ROUND(AVG(mort30_flag)*100,1) AS mort30_rate_percent,
  ROUND(AVG(cardio_flag)*100,1) AS cardio_complication_rate_percent,
  ROUND(AVG(neuro_flag)*100,1) AS neuro_complication_rate_percent,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 0 THEN los_days END),2) AS mean_survivor_los_days
FROM grp
WHERE cohort IS NOT NULL
GROUP BY cohort
UNION ALL
-- Matched profile percentile
SELECT
  'PE_high_comorb_percentile_vs_control' AS cohort,
  NULL AS n_adm,
  NULL AS mean_comorbidity_score,
  NULL AS mort30_rate_percent,
  NULL AS cardio_complication_rate_percent,
  NULL AS neuro_complication_rate_percent,
  NULL AS mean_survivor_los_days
FROM (
  SELECT
    comorbidity_count,
    PERCENT_RANK() OVER (ORDER BY comorbidity_count) AS perc_rank
  FROM grp
  WHERE cohort = 'Control'
) ctrl
JOIN (
  SELECT comorbidity_count
  FROM grp
  WHERE cohort = 'PE_high_comorb'
  LIMIT 1
) pe
ON ctrl.comorbidity_count <= pe.comorbidity_count
LIMIT 1;