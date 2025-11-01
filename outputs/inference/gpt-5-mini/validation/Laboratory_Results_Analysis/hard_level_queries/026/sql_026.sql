WITH
-- Identify admissions that meet cohort criteria (male, age 75-85, hepatic failure diagnosis)
cohort_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
        AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (LOWER(di.long_title) LIKE '%hepatic%' AND LOWER(di.long_title) LIKE '%fail%')
          OR LOWER(di.long_title) LIKE '%liver failure%'
        )
    )
),

-- Map ICU chartevents to vital types within first 48 hours of admission
vitals_48h AS (
  SELECT
    ca.hadm_id,
    ce.charttime,
    di.itemid,
    di.label AS item_label,
    ce.valuenum,
    -- classify into a canonical vital type via pattern matching on d_items.label
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' OR LOWER(di.label) LIKE '%hr %' OR LOWER(di.label) = 'hr' THEN 'hr'
      WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%respirations%' THEN 'rr'
      WHEN LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%o2 sat%' THEN 'spo2'
      WHEN LOWER(di.label) LIKE '%temperature%' OR LOWER(di.label) LIKE '%temp%' THEN 'temp'
      WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN 'map'
      WHEN LOWER(di.label) LIKE '%systolic%' OR LOWER(di.label) LIKE '%sbp%' OR LOWER(di.label) LIKE '%arterial systolic%' THEN 'sbp'
      ELSE NULL
    END AS vital_type
  FROM
    cohort_admissions ca
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.hadm_id = ca.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    USING(itemid)
  WHERE
    ce.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    -- keep only recognized vital types
    AND (
      LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%hr %'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%resp rate%'
      OR LOWER(di.label) LIKE '%oxygen saturation%'
      OR LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%temperature%'
      OR LOWER(di.label) LIKE '%temp%'
      OR LOWER(di.label) LIKE '%mean arterial pressure%'
      OR LOWER(di.label) LIKE '%map%'
      OR LOWER(di.label) LIKE '%systolic%'
      OR LOWER(di.label) LIKE '%sbp%'
    )
),

-- Compute per-admission instability component flags and a summed instability score
admission_instability AS (
  SELECT
    ca.hadm_id,
    -- component flags: 0/1
    MAX(CASE WHEN v.vital_type = 'hr' AND v.valuenum > 100 THEN 1 ELSE 0 END) AS flag_hr_tachy,
    MAX(CASE WHEN v.vital_type = 'rr' AND v.valuenum > 20 THEN 1 ELSE 0 END) AS flag_rr_tachy,
    MAX(CASE WHEN (v.vital_type = 'sbp' AND v.valuenum < 90) OR (v.vital_type = 'map' AND v.valuenum < 65) THEN 1 ELSE 0 END) AS flag_hypotension,
    MAX(CASE WHEN v.vital_type = 'spo2' AND v.valuenum < 90 THEN 1 ELSE 0 END) AS flag_hypoxia,
    MAX(CASE WHEN v.vital_type = 'temp' AND (v.valuenum < 36 OR v.valuenum > 38) THEN 1 ELSE 0 END) AS flag_temp,
    -- baseline fields for aggregation
    ca.hospital_expire_flag,
    ca.admittime,
    ca.dischtime
  FROM
    cohort_admissions ca
  LEFT JOIN
    vitals_48h v
    USING(hadm_id)
  GROUP BY
    ca.hadm_id, ca.hospital_expire_flag, ca.admittime, ca.dischtime
),

-- Sum flags into an instability_score per admission (0-5)
admission_scores AS (
  SELECT
    hadm_id,
    (IFNULL(flag_hr_tachy,0) + IFNULL(flag_rr_tachy,0) + IFNULL(flag_hypotension,0) + IFNULL(flag_hypoxia,0) + IFNULL(flag_temp,0)) AS instability_score,
    hospital_expire_flag,
    admittime,
    dischtime
  FROM
    admission_instability
),

-- Cohort summary metrics (maximum instability score, mortality rate, average LOS)
cohort_summary AS (
  SELECT
    COUNT(*) AS cohort_n,
    MAX(instability_score) AS cohort_max_instability,
    ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS cohort_mortality_pct,
    ROUND( AVG( TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0 ), 2) AS cohort_avg_los_days
  FROM
    admission_scores
),

-- Prepare lab events (first 48 hours) for cohort and for all admissions
-- Map lab items to lab types of interest
lab_events_48h AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    dl.itemid,
    dl.label AS lab_label,
    CASE
      WHEN LOWER(dl.label) LIKE '%bilirubin%' THEN 'bilirubin'
      WHEN LOWER(dl.label) LIKE '%inr%' OR LOWER(dl.label) LIKE '%pt(inr)%' OR LOWER(dl.label) LIKE '%pt/inr%' THEN 'inr'
      WHEN LOWER(dl.label) LIKE '%lactate%' THEN 'lactate'
      WHEN LOWER(dl.label) LIKE '%creatinine%' THEN 'creatinine'
      WHEN LOWER(dl.label) LIKE '%platelet%' THEN 'platelets'
      ELSE NULL
    END AS lab_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    USING(itemid)
  WHERE
    le.valuenum IS NOT NULL
    AND (
      LOWER(dl.label) LIKE '%bilirubin%'
      OR LOWER(dl.label) LIKE '%inr%'
      OR LOWER(dl.label) LIKE '%pt(inr)%'
      OR LOWER(dl.label) LIKE '%lactate%'
      OR LOWER(dl.label) LIKE '%creatinine%'
      OR LOWER(dl.label) LIKE '%platelet%'
    )
),

-- Join lab events to admissions to restrict to first 48 hours after admittime
labs_48h_linked AS (
  SELECT
    le.hadm_id,
    le.lab_type,
    le.valuenum,
    a.admittime,
    le.charttime
  FROM
    lab_events_48h le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE
    le.lab_type IS NOT NULL
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),

-- Determine per-admission abnormal lab flags (for each lab type)
admission_lab_flags AS (
  SELECT
    hadm_id,
    lab_type,
    MAX(
      CASE
        WHEN lab_type = 'bilirubin' AND valuenum > 2 THEN 1
        WHEN lab_type = 'inr' AND valuenum > 1.5 THEN 1
        WHEN lab_type = 'lactate' AND valuenum > 2 THEN 1
        WHEN lab_type = 'creatinine' AND valuenum > 1.5 THEN 1
        WHEN lab_type = 'platelets' AND valuenum < 100 THEN 1
        ELSE 0
      END
    ) AS any_abnormal
  FROM
    labs_48h_linked
  GROUP BY
    hadm_id, lab_type
),

-- Cohort lab abnormal counts: which cohort admissions had abnormalities
cohort_lab_stats AS (
  SELECT
    al.lab_type,
    COUNT(DISTINCT CASE WHEN al.any_abnormal = 1 THEN al.hadm_id END) AS cohort_abn_count,
    COUNT(DISTINCT ca.hadm_id) AS cohort_total_admissions
  FROM
    admission_lab_flags al
  RIGHT JOIN
    cohort_admissions ca
    ON al.hadm_id = ca.hadm_id
    AND al.lab_type IS NOT NULL
  GROUP BY
    al.lab_type
),

-- General (all admissions) lab abnormal counts
general_lab_stats AS (
  SELECT
    al.lab_type,
    COUNT(DISTINCT CASE WHEN al.any_abnormal = 1 THEN al.hadm_id END) AS general_abn_count,
    COUNT(DISTINCT a.hadm_id) AS general_total_admissions
  FROM
    admission_lab_flags al
  RIGHT JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON al.hadm_id = a.hadm_id
    AND al.lab_type IS NOT NULL
  GROUP BY
    al.lab_type
),

-- Merge cohort and general lab stats into a single table
lab_comparison AS (
  SELECT
    COALESCE(c.lab_type, g.lab_type) AS lab_type,
    COALESCE(c.cohort_abn_count, 0) AS cohort_abn_count,
    COALESCE(c.cohort_total_admissions, (SELECT COUNT(*) FROM cohort_admissions)) AS cohort_total_admissions,
    COALESCE(g.general_abn_count, 0) AS general_abn_count,
    COALESCE(g.general_total_admissions, (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.admissions`)) AS general_total_admissions
  FROM
    cohort_lab_stats c
  FULL OUTER JOIN
    general_lab_stats g
  ON c.lab_type = g.lab_type
)

-- Final outputs combined into one result set: 1) cohort summary row, 2) lab comparison rows
SELECT
  'cohort_summary' AS result_type,
  cs.cohort_n,
  cs.cohort_max_instability,
  cs.cohort_mortality_pct,
  cs.cohort_avg_los_days,
  NULL AS lab,
  NULL AS cohort_abnormal_count,
  NULL AS cohort_admissions,
  NULL AS cohort_abnormal_pct,
  NULL AS general_abnormal_count,
  NULL AS general_admissions,
  NULL AS general_abnormal_pct
FROM
  cohort_summary cs

UNION ALL

SELECT
  'lab_comparison' AS result_type,
  NULL AS cohort_n,
  NULL AS cohort_max_instability,
  NULL AS cohort_mortality_pct,
  NULL AS cohort_avg_los_days,
  lc.lab_type AS lab,
  lc.cohort_abn_count AS cohort_abnormal_count,
  lc.cohort_total_admissions AS cohort_admissions,
  SAFE_DIVIDE(lc.cohort_abn_count, lc.cohort_total_admissions) * 100.0 AS cohort_abnormal_pct,
  lc.general_abn_count AS general_abnormal_count,
  lc.general_total_admissions AS general_admissions,
  SAFE_DIVIDE(lc.general_abn_count, lc.general_total_admissions) * 100.0 AS general_abnormal_pct
FROM
  lab_comparison lc
ORDER BY
  result_type,
  lab;