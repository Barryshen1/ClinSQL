WITH
-- 1) admissions with patient info
pat_adm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.anchor_age BETWEEN 65 AND 75
    AND p.gender = 'F'
    -- ensure LOS >= 96 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96
),

-- 2) admissions that have both diabetes and heart failure diagnoses
adm_with_dx AS (
  SELECT
    pa.*,
    pa.admittime AS admittime,
    pa.dischtime AS dischtime
  FROM pat_adm pa
  JOIN (
    -- find hadm_ids that have both diabetes and heart failure diagnoses
    SELECT
      d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%'
      OR LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
    GROUP BY d.hadm_id
    HAVING
      SUM(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%' THEN 1 ELSE 0 END) > 0
      AND SUM(CASE WHEN LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%' THEN 1 ELSE 0 END) > 0
  ) has_both
    ON pa.hadm_id = has_both.hadm_id
),

-- 3) union inpatient medication/order/admin records (prescriptions, pharmacy, emar)
med_events AS (
  -- prescriptions
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    stoptime AS med_stop,
    LOWER(COALESCE(drug, '')) AS med_name,
    'prescription' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- pharmacy orders/dispensations
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    stoptime AS med_stop,
    LOWER(COALESCE(medication, '')) AS med_name,
    'pharmacy' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- emar administration events (point-in-time)
  SELECT
    subject_id,
    hadm_id,
    charttime AS med_time,
    NULL AS med_stop,
    LOWER(COALESCE(medication, '')) AS med_name,
    'emar' AS source
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE hadm_id IS NOT NULL
),

-- 4) restrict med events to our admissions and classify med type by keyword heuristics
med_events_in_adm AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.med_time,
    m.med_stop,
    m.med_name,
    m.source,
    -- classify into basal / bolus / sliding keywords (may match multiple)
    CASE
      WHEN (m.med_name LIKE '%glargine%' OR m.med_name LIKE '%detemir%' OR m.med_name LIKE '%degludec%'
            OR m.med_name LIKE '%lantus%' OR m.med_name LIKE '%levemir%' OR m.med_name LIKE '%nph%'
            OR m.med_name LIKE '%basal%') THEN 1 ELSE 0 END AS is_basal,
    CASE
      WHEN (m.med_name LIKE '%lispro%' OR m.med_name LIKE '%aspart%' OR m.med_name LIKE '%glulisin%'
            OR m.med_name LIKE '%regular insulin%' OR m.med_name LIKE '%regular%'
            OR m.med_name LIKE '%humalog%' OR m.med_name LIKE '%novolog%' OR m.med_name LIKE '%rapid%') THEN 1 ELSE 0 END AS is_bolus,
    CASE
      WHEN (m.med_name LIKE '%sliding%' OR m.med_name LIKE '%ssi%' OR m.med_name LIKE '%scale%') THEN 1 ELSE 0 END AS is_sliding
  FROM med_events m
  JOIN adm_with_dx a
    ON m.hadm_id = a.hadm_id
),

-- 5) For each admission compute presence flags in early (first 48h) and final (last 48h) windows.
med_window_flags AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- early window bounds
    a.admittime AS early_start,
    TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) AS early_end,
    -- final window bounds
    TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AS final_start,
    a.dischtime AS final_end,
    -- flags computed by checking overlap for orders with med_stop and point events for emar
    MAX(CASE WHEN
          (is_basal = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)) -- point or start inside
              OR (med_time IS NOT NULL AND med_time <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) AND (med_stop IS NULL OR med_stop >= a.admittime))
            )
          )
          THEN 1 ELSE 0 END) AS early_basal,
    MAX(CASE WHEN
          (is_bolus = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR))
              OR (med_time IS NOT NULL AND med_time <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) AND (med_stop IS NULL OR med_stop >= a.admittime))
            )
          )
          THEN 1 ELSE 0 END) AS early_bolus,
    MAX(CASE WHEN
          (is_sliding = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR))
              OR (med_time IS NOT NULL AND med_time <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR) AND (med_stop IS NULL OR med_stop >= a.admittime))
            )
          )
          THEN 1 ELSE 0 END) AS early_sliding,
    MAX(CASE WHEN
          (is_basal = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime)
              OR (med_time IS NOT NULL AND med_time <= a.dischtime AND (med_stop IS NULL OR med_stop >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR)))
            )
          )
          THEN 1 ELSE 0 END) AS final_basal,
    MAX(CASE WHEN
          (is_bolus = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime)
              OR (med_time IS NOT NULL AND med_time <= a.dischtime AND (med_stop IS NULL OR med_stop >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR)))
            )
          )
          THEN 1 ELSE 0 END) AS final_bolus,
    MAX(CASE WHEN
          (is_sliding = 1
            AND (
              (med_time IS NOT NULL AND med_time BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime)
              OR (med_time IS NOT NULL AND med_time <= a.dischtime AND (med_stop IS NULL OR med_stop >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR)))
            )
          )
          THEN 1 ELSE 0 END) AS final_sliding
  FROM adm_with_dx a
  LEFT JOIN med_events_in_adm m
    ON a.hadm_id = m.hadm_id
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),

-- 6) Map flags to one regimen category per window per admission
adm_categories AS (
  SELECT
    hadm_id,
    subject_id,
    -- early category
    CASE
      WHEN early_basal = 1 AND early_bolus = 1 THEN 'basal-bolus'
      WHEN early_sliding = 1 AND early_basal = 0 AND early_bolus = 0 THEN 'sliding-scale'
      WHEN early_basal = 1 THEN 'basal'
      WHEN early_bolus = 1 THEN 'bolus'
      ELSE 'none'
    END AS early_cat,
    -- final category
    CASE
      WHEN final_basal = 1 AND final_bolus = 1 THEN 'basal-bolus'
      WHEN final_sliding = 1 AND final_basal = 0 AND final_bolus = 0 THEN 'sliding-scale'
      WHEN final_basal = 1 THEN 'basal'
      WHEN final_bolus = 1 THEN 'bolus'
      ELSE 'none'
    END AS final_cat
  FROM med_window_flags
),

-- 7) compute cohort size (admission-level)
cohort_n AS (
  SELECT COUNT(DISTINCT hadm_id) AS cohort_count FROM adm_categories
),

-- 8) counts by regimen in early and final windows (we will report only the 4 regimens requested)
regimen_counts AS (
  SELECT
    rc.regimen,
    SUM(CASE WHEN early_cat = rc.regimen THEN 1 ELSE 0 END) AS early_count,
    SUM(CASE WHEN final_cat = rc.regimen THEN 1 ELSE 0 END) AS final_count
  FROM adm_categories ac
  CROSS JOIN (SELECT 'basal' AS regimen UNION ALL SELECT 'bolus' UNION ALL SELECT 'basal-bolus' UNION ALL SELECT 'sliding-scale') rc
  GROUP BY rc.regimen
),

-- 9) transition counts among the four regimens (early -> final)
transitions AS (
  SELECT
    early_cat,
    final_cat,
    COUNT(*) AS trans_count
  FROM adm_categories
  WHERE early_cat IN ('basal','bolus','basal-bolus','sliding-scale')
    AND final_cat IN ('basal','bolus','basal-bolus','sliding-scale')
  GROUP BY early_cat, final_cat
)

-- Final outputs: (A) regimen percentages early vs final; (B) early->final transition counts / pct of cohort
SELECT
  'A_regimen_percentages' AS table_part,
  regimen AS early_or_transition,
  NULL AS final_category,
  early_count,
  ROUND(100.0 * SAFE_DIVIDE(early_count, (SELECT cohort_count FROM cohort_n)), 2) AS early_pct,
  final_count,
  ROUND(100.0 * SAFE_DIVIDE(final_count, (SELECT cohort_count FROM cohort_n)), 2) AS final_pct,
  (SELECT cohort_count FROM cohort_n) AS cohort_size,
  NULL AS transition_count,
  NULL AS transition_pct
FROM regimen_counts

UNION ALL

SELECT
  'B_transitions' AS table_part,
  early_cat AS early_or_transition,
  final_cat AS final_category,
  NULL AS early_count,
  NULL AS early_pct,
  NULL AS final_count,
  NULL AS final_pct,
  (SELECT cohort_count FROM cohort_n) AS cohort_size,
  trans_count AS transition_count,
  ROUND(100.0 * SAFE_DIVIDE(trans_count, (SELECT cohort_count FROM cohort_n)), 2) AS transition_pct
FROM transitions
ORDER BY table_part, early_or_transition, final_category;