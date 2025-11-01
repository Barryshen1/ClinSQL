WITH all_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    i.stay_id,
    i.intime,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432'))
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
        )
    ) THEN 1 ELSE 0 END AS has_ich
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

sofa_scores AS (
  SELECT
    ap.subject_id,
    ce.value AS sofacore
  FROM all_patients ap
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ap.stay_id = ce.stay_id
  WHERE
    ce.itemid = 223900
    AND ce.charttime BETWEEN ap.intime AND DATETIME_ADD(ap.intime, INTERVAL 24 HOUR)
),

sofa_max AS (
  SELECT
    subject_id,
    MAX(sofacore) AS max_sofa
  FROM sofa_scores
  GROUP BY subject_id
),

sepsis AS (
  SELECT
    ap.subject_id,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        d.subject_id = ap.subject_id
        AND d.hadm_id = ap.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code IN ('99591', '99592'))
          OR (d.icd_version = 10 AND d.icd_code IN ('A419', 'R6520'))
        )
    ) THEN 1 ELSE 0 END AS has_sepsis
  FROM all_patients ap
),

los_survivors AS (
  SELECT
    subject_id,
    CASE
      WHEN deathtime IS NULL OR deathtime > DATETIME_ADD(admittime, INTERVAL 90 DAY)
        THEN DATETIME_DIFF(dischtime, admittime, DAY)
      ELSE NULL
    END AS los
  FROM all_patients
),

mortality_90day AS (
  SELECT
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL AND deathtime <= DATETIME_ADD(admittime, INTERVAL 90 DAY)
        THEN 1
      ELSE 0
    END AS died_within_90
  FROM all_patients
),

comparison_sofa AS (
  SELECT max_sofa
  FROM all_patients ap
  LEFT JOIN sofa_max sm ON ap.subject_id = sm.subject_id
  WHERE ap.has_ich = 0 AND sm.max_sofa IS NOT NULL
),

main_median_sofa AS (
  SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sm.max_sofa) AS median_sofa
  FROM all_patients ap
  LEFT JOIN sofa_max sm ON ap.subject_id = sm.subject_id
  WHERE ap.has_ich = 1 AND sm.max_sofa IS NOT NULL
),

main_cohort AS (
  SELECT
    'Main Cohort (ICH)' AS cohort,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sm.max_sofa) AS median_sofa,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sm.max_sofa) AS q1_sofa,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sm.max_sofa) AS q3_sofa,
    (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sm.max_sofa) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sm.max_sofa)) AS iqr_sofa,
    AVG(m.died_within_90) AS mortality_90day,
    AVG(s.has_sepsis) AS major_complication_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.los) AS median_survivor_los
  FROM all_patients ap
  LEFT JOIN sofa_max sm ON ap.subject_id = sm.subject_id
  LEFT JOIN sepsis s ON ap.subject_id = s.subject_id
  LEFT JOIN los_survivors l ON ap.subject_id = l.subject_id
  LEFT JOIN mortality_90day m ON ap.subject_id = m.subject_id
  WHERE ap.has_ich = 1
),

comparison_cohort AS (
  SELECT
    'Comparison Cohort (All Female 44-54)' AS cohort,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sm.max_sofa) AS median_sofa,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sm.max_sofa) AS q1_sofa,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sm.max_sofa) AS q3_sofa,
    (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sm.max_sofa) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sm.max_sofa)) AS iqr_sofa,
    AVG(m.died_within_90) AS mortality_90day,
    AVG(s.has_sepsis) AS major_complication_rate,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.los) AS median_survivor_los
  FROM all_patients ap
  LEFT JOIN sofa_max sm ON ap.subject_id = sm.subject_id
  LEFT JOIN sepsis s ON ap.subject_id = s.subject_id
  LEFT JOIN los_survivors l ON ap.subject_id = l.subject_id
  LEFT JOIN mortality_90day m ON ap.subject_id = m.subject_id
  WHERE ap.has_ich = 0
),

matched_risk_percentile AS (
  SELECT
    (SELECT COUNT(*) FROM comparison_sofa WHERE max_sofa <= (SELECT median_sofa FROM main_median_sofa)) * 100.0 / COUNT(*)
  FROM comparison_sofa
)

SELECT * FROM main_cohort
UNION ALL
SELECT * FROM comparison_cohort
UNION ALL
SELECT
  'Matched Risk Percentile' AS cohort,
  NULL AS median_sofa,
  NULL AS q1_sofa,
  NULL AS q3_sofa,
  NULL AS iqr_sofa,
  NULL AS mortality_90day,
  NULL AS major_complication_rate,
  NULL AS median_survivor_los,
  (SELECT * FROM matched_risk_percentile) AS matched_risk_percentile;