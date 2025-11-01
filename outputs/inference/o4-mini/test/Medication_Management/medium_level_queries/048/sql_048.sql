WITH
-- 1. Base cohort: female, age 65–75, LOS ≥96h, with diabetes and HF diagnoses
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%heart failure%'
    )
),
-- 2. All insulin prescriptions with classification (filtering out NULL regimens)
insulin_rx AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    regimen
  FROM (
    SELECT
      bc.subject_id,
      bc.hadm_id,
      rx.starttime,
      CASE
        WHEN LOWER(rx.drug) LIKE '%glargine%' OR LOWER(rx.drug) LIKE '%detemir%' OR LOWER(rx.drug) LIKE '%degludec%' THEN 'basal'
        WHEN LOWER(rx.drug) LIKE '%lispro%' OR LOWER(rx.drug) LIKE '%aspart%' OR LOWER(rx.drug) LIKE '%glulisine%' OR LOWER(rx.drug) LIKE '%regular%' THEN 'bolus'
        WHEN LOWER(rx.drug) LIKE '%sliding%' THEN 'sliding-scale'
        ELSE NULL
      END AS regimen
    FROM
      base_cohort bc
      JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
        ON bc.subject_id = rx.subject_id
        AND bc.hadm_id = rx.hadm_id
    WHERE
      LOWER(rx.drug) LIKE '%insulin%'
      AND (
        LOWER(rx.drug) LIKE '%glargine%'
        OR LOWER(rx.drug) LIKE '%detemir%'
        OR LOWER(rx.drug) LIKE '%degludec%'
        OR LOWER(rx.drug) LIKE '%lispro%'
        OR LOWER(rx.drug) LIKE '%aspart%'
        OR LOWER(rx.drug) LIKE '%glulisine%'
        OR LOWER(rx.drug) LIKE '%regular%'
        OR LOWER(rx.drug) LIKE '%sliding%'
      )
  )
  WHERE regimen IS NOT NULL
),
-- 3. Flag each record as early vs late
rx_periods AS (
  SELECT
    ir.subject_id,
    ir.hadm_id,
    ir.regimen,
    CASE
      WHEN ir.starttime < TIMESTAMP_ADD(bc.admittime, INTERVAL 48 HOUR) THEN 'early'
      WHEN ir.starttime >= TIMESTAMP_SUB(bc.dischtime, INTERVAL 48 HOUR) THEN 'late'
      ELSE NULL
    END AS period
  FROM
    insulin_rx ir
    JOIN base_cohort bc
      USING(subject_id, hadm_id)
),
-- 4. Determine per-patient per-period regimen category
patient_period_regimen AS (
  SELECT
    subject_id,
    hadm_id,
    period,
    ARRAY_AGG(DISTINCT regimen) AS seen
  FROM
    rx_periods
  WHERE
    period IN ('early', 'late')
  GROUP BY
    subject_id, hadm_id, period
),
-- 5. Collapse to single label per period
patient_period_label AS (
  SELECT
    subject_id,
    hadm_id,
    period,
    CASE
      WHEN 'basal' IN UNNEST(seen) AND 'bolus' IN UNNEST(seen) THEN 'basal–bolus'
      WHEN 'basal' IN UNNEST(seen) THEN 'basal'
      WHEN 'bolus' IN UNNEST(seen) THEN 'bolus'
      WHEN 'sliding-scale' IN UNNEST(seen) THEN 'sliding-scale'
      ELSE 'none'
    END AS label
  FROM
    patient_period_regimen
),
-- 6. Pivot labels into early vs late per patient
patient_labels AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(IF(period = 'early', label, NULL)) AS early_label,
    MAX(IF(period = 'late',  label, NULL)) AS late_label
  FROM
    patient_period_label
  GROUP BY
    subject_id, hadm_id
),
-- 7. Cohort size (excluding those with no regimen ever)
cohort_n AS (
  SELECT COUNT(*) AS n
  FROM patient_labels
  WHERE early_label != 'none'
     OR late_label  != 'none'
),
-- 8. Early vs late regimen counts
period_stats AS (
  SELECT
    period,
    label,
    COUNT(*) AS cnt
  FROM (
    SELECT subject_id, hadm_id, early_label AS label, 'early' AS period FROM patient_labels
    UNION ALL
    SELECT subject_id, hadm_id, late_label  AS label, 'late'  AS period FROM patient_labels
  )
  WHERE label != 'none'
  GROUP BY period, label
),
-- 9. Early→late transitions
transition_stats AS (
  SELECT
    early_label,
    late_label,
    COUNT(*) AS cnt
  FROM patient_labels
  WHERE early_label != 'none' OR late_label != 'none'
  GROUP BY early_label, late_label
)

-- 10. Final reporting: percentages and raw counts
SELECT
  ps.period,
  ps.label,
  ps.cnt,
  ROUND(100 * ps.cnt / cn.n, 1) AS pct_of_cohort
FROM
  period_stats ps
  CROSS JOIN cohort_n cn
ORDER BY
  ps.period,
  ps.label;

-- Transitions (run separately if desired):
-- SELECT
--   early_label,
--   late_label,
--   cnt
-- FROM
--   transition_stats
-- ORDER BY
--   early_label, late_label;