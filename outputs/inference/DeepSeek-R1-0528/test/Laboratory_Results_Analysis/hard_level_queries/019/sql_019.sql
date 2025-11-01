WITH predefined_labs AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label IN (
    'Amylase', 'Lipase', 'White Blood Cells', 'C-Reactive Protein (CRP)',
    'Hematocrit', 'BUN', 'Creatinine', 'Calcium', 'Lactate'
  )
), cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code = '5770') OR
          (di.icd_version = 10 AND di.icd_code LIKE 'K85%')
        )
    )
), filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admit BETWEEN 63 AND 73
), instability_scores AS (
  SELECT
    fc.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL  -- Abnormal result
  GROUP BY fc.hadm_id
), percentile_90 AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90
  FROM instability_scores
  LIMIT 1
), high_score_group AS (
  SELECT hadm_id
  FROM instability_scores
  CROSS JOIN percentile_90
  WHERE instability_score >= p90
), mortality_los AS (
  SELECT
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM high_score_group)
), labs_high_score AS (
  SELECT
    pl.label AS lab_name,
    le.itemid,
    COUNT(*) AS total_tests_high,
    SUM(CASE WHEN le.flag IS NOT NULL THEN 1 ELSE 0 END) AS critical_tests_high
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN predefined_labs pl
    ON le.itemid = pl.itemid
  WHERE le.hadm_id IN (SELECT hadm_id FROM high_score_group)
  GROUP BY pl.label, le.itemid
), labs_general AS (
  SELECT
    le.itemid,
    COUNT(*) AS total_tests_general,
    SUM(CASE WHEN le.flag IS NOT NULL THEN 1 ELSE 0 END) AS critical_tests_general
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.hadm_id IS NOT NULL  -- All inpatients
    AND le.itemid IN (SELECT itemid FROM predefined_labs)
  GROUP BY le.itemid
)
SELECT
  ml.mortality_rate,
  ml.mean_los,
  lhs.lab_name,
  SAFE_DIVIDE(lhs.critical_tests_high, lhs.total_tests_high) * 100 AS critical_rate_high,
  SAFE_DIVIDE(lg.critical_tests_general, lg.total_tests_general) * 100 AS critical_rate_general
FROM mortality_los ml
CROSS JOIN labs_high_score lhs
INNER JOIN labs_general lg
  ON lhs.itemid = lg.itemid;