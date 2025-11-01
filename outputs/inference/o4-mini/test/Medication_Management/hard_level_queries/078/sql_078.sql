WITH
-- 1. Identify PE admissions in elderly female patients
pe_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
    AND LOWER(dd.long_title) LIKE '%pulmonary embol%'
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

-- 2. Medication complexity: count of distinct prescriptions in first 24h
meds_first24 AS (
  SELECT
    rx.hadm_id,
    COUNT(DISTINCT CONCAT(rx.drug, '/', rx.dose_unit_rx, '/', rx.route)) AS med_complexity
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    JOIN pe_admissions pa
      ON rx.hadm_id = pa.hadm_id
  WHERE
    rx.starttime BETWEEN pa.admittime
      AND TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    rx.hadm_id
),

-- 3a. QT‐prolonging drug list
qt_drugs AS (
  SELECT 'amiodarone' AS drug UNION ALL
  SELECT 'sotalol' UNION ALL
  SELECT 'dofetilide' UNION ALL
  SELECT 'quinidine'
),

-- 3b. Bleeding‐risk drug list
bleed_drugs AS (
  SELECT 'heparin' AS drug UNION ALL
  SELECT 'enoxaparin' UNION ALL
  SELECT 'warfarin' UNION ALL
  SELECT 'apixaban' UNION ALL
  SELECT 'rivaroxaban'
),

-- 3c. Flag presence of QT and bleeding drugs in first 24h
drug_flags AS (
  SELECT
    pa.hadm_id,
    MAX(CASE WHEN EXISTS (
           SELECT 1 FROM qt_drugs q
           WHERE LOWER(rx.drug) = q.drug
         ) THEN 1 ELSE 0 END) AS has_qt_drug,
    MAX(CASE WHEN EXISTS (
           SELECT 1 FROM bleed_drugs b
           WHERE LOWER(rx.drug) = b.drug
         ) THEN 1 ELSE 0 END) AS has_bleed_drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    JOIN pe_admissions pa
      ON rx.hadm_id = pa.hadm_id
  WHERE
    rx.starttime BETWEEN pa.admittime
      AND TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    pa.hadm_id
),

-- 4. ICU admission flag
icu_flag AS (
  SELECT
    hadm_id,
    1 AS icu_admitted
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),

-- 5. Combine metrics
cohort_metrics AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    pa.hospital_expire_flag,
    COALESCE(m.med_complexity, 0)         AS med_complexity,
    COALESCE(d.has_qt_drug, 0)           AS has_qt_drug,
    COALESCE(d.has_bleed_drug, 0)        AS has_bleed_drug,
    IFNULL(icu.icu_admitted, 0)          AS icu_flag
  FROM
    pe_admissions pa
    LEFT JOIN meds_first24 m USING (hadm_id)
    LEFT JOIN drug_flags d USING (hadm_id)
    LEFT JOIN icu_flag icu USING (hadm_id)
),

-- 6. Medication complexity quartiles
med_quarts AS (
  SELECT
    APPROX_QUANTILES(med_complexity, 4) AS quants
  FROM
    cohort_metrics
),

-- 7. LOS quartiles
los_quarts AS (
  SELECT
    APPROX_QUANTILES(los_days, 4) AS quants
  FROM
    cohort_metrics
)

-- Final aggregation
SELECT
  -- Overall complexity distribution
  AVG(cm.med_complexity)                    AS complexity_mean,
  MIN(cm.med_complexity)                    AS complexity_min,
  MAX(cm.med_complexity)                    AS complexity_max,
  STDDEV_POP(cm.med_complexity)             AS complexity_sd,

  -- Prevalence of QT‐prolonging and bleeding‐risk drugs
  100.0 * SUM(cm.has_qt_drug) / COUNT(*)     AS pct_with_qt_drug,
  100.0 * SUM(cm.has_bleed_drug) / COUNT(*)  AS pct_with_bleed_drug,

  -- Complexity percentiles from precomputed quartiles
  mq.quants[OFFSET(1)]                       AS p25_complexity,
  mq.quants[OFFSET(2)]                       AS p50_complexity,
  mq.quants[OFFSET(3)]                       AS p75_complexity,

  -- ICU vs non‐ICU comparison
  AVG(IF(cm.icu_flag=1, cm.med_complexity, NULL)) AS icu_complexity_mean,
  AVG(IF(cm.icu_flag=0, cm.med_complexity, NULL)) AS nonicu_complexity_mean,
  100.0 * SUM(IF(cm.icu_flag=1 AND cm.has_qt_drug=1,1,0))
           / NULLIF(SUM(IF(cm.icu_flag=1,1,0)),0)   AS icu_pct_qt,
  100.0 * SUM(IF(cm.icu_flag=0 AND cm.has_qt_drug=1,1,0))
           / NULLIF(SUM(IF(cm.icu_flag=0,1,0)),0)   AS nonicu_pct_qt,

  -- Top‐quartile LOS and mortality among top‐quartile stays
  SAFE_DIVIDE(
    SUM(
      IF(cm.los_days >= lq.quants[OFFSET(3)]
         AND cm.hospital_expire_flag=1, 1, 0)
    ),
    SUM(
      IF(cm.los_days >= lq.quants[OFFSET(3)], 1, 0)
    )
  ) * 100.0 AS top_quartile_mortality_pct

FROM
  cohort_metrics cm
CROSS JOIN
  med_quarts mq
CROSS JOIN
  los_quarts lq;