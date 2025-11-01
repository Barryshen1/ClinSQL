WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 74 AND 84
),

meds_24h AS (
  -- medications started within first 24 hours of admission
  SELECT
    c.hadm_id,
    LOWER(TRIM(prescriptions.drug)) AS med_name
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` prescriptions
    ON prescriptions.hadm_id = c.hadm_id
   AND prescriptions.starttime IS NOT NULL
   AND prescriptions.starttime BETWEEN c.admittime
                                 AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  WHERE prescriptions.drug IS NOT NULL
),

per_admission AS (
  -- per-admission complexity and drug-risk flags
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.anchor_age,
    COALESCE(meds.complexity, 0) AS complexity,
    COALESCE(meds.qt_flag, 0) AS qt_flag,
    COALESCE(meds.bleed_flag, 0) AS bleed_flag,
    -- ICU flag: 1 if there exists any ICU stay for this hadm_id
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = c.hadm_id
    ) THEN 1 ELSE 0 END AS icu_flag,
    -- LOS in hours (integer)
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) AS los_hours
  FROM cohort c
  LEFT JOIN (
    SELECT
      hadm_id,
      COUNT(DISTINCT med_name) AS complexity,
      -- QT-prolonging drugs (illustrative list - expand as needed)
      MAX(
        CASE WHEN REGEXP_CONTAINS(med_name,
          r'(levofloxacin|moxifloxacin|ciprofloxacin|azithromycin|fluconazole|ondansetron|amiodarone|sotalol|haloperidol|methadone|quinidine|procainamide|chloroquine|hydroxychloroquine)'
        ) THEN 1 ELSE 0 END
      ) AS qt_flag,
      -- Bleeding risk drugs (illustrative list - expand as needed)
      MAX(
        CASE WHEN REGEXP_CONTAINS(med_name,
          r'(warfarin|heparin|enoxaparin|dalteparin|apixaban|rivaroxaban|dabigatran|edoxaban|aspirin|clopidogrel|ticagrelor|prasugrel)'
        ) THEN 1 ELSE 0 END
      ) AS bleed_flag
    FROM meds_24h
    GROUP BY hadm_id
  ) meds
  USING (hadm_id)
),

-- overall quantile thresholds for complexity and LOS
quantiles AS (
  SELECT
    APPROX_QUANTILES(complexity, 4) AS complexity_q,
    APPROX_QUANTILES(los_hours, 4) AS los_q
  FROM per_admission
),

-- derive quartile thresholds into scalars
thresholds AS (
  SELECT
    complexity_q[OFFSET(1)] AS complexity_q1,
    complexity_q[OFFSET(2)] AS complexity_median,
    complexity_q[OFFSET(3)] AS complexity_q3,
    los_q[OFFSET(1)] AS los_q1,
    los_q[OFFSET(2)] AS los_median,
    los_q[OFFSET(3)] AS los_q3
  FROM quantiles
),

-- mean complexity per quartile bucket (based on overall thresholds)
quartile_assign AS (
  SELECT
    pa.*,
    t.complexity_q1,
    t.complexity_median,
    t.complexity_q3,
    CASE
      WHEN pa.complexity <= t.complexity_q1 THEN 1
      WHEN pa.complexity <= t.complexity_median THEN 2
      WHEN pa.complexity <= t.complexity_q3 THEN 3
      ELSE 4
    END AS complexity_quartile
  FROM per_admission pa
  CROSS JOIN thresholds t
)

-- Final outputs: multiple labeled result rows combined with UNION ALL
SELECT
  'overall' AS group_label,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity), 3) AS mean_complexity,
  MIN(complexity) AS min_complexity,
  MAX(complexity) AS max_complexity,
  ROUND(STDDEV_POP(complexity), 3) AS sd_complexity,
  ROUND(100.0 * SUM(qt_flag) / COUNT(*), 2) AS pct_with_qt_drug,
  ROUND(100.0 * SUM(bleed_flag) / COUNT(*), 2) AS pct_with_bleed_drug,
  -- quartiles
  t.complexity_q1 AS complexity_q1,
  t.complexity_median AS complexity_median,
  t.complexity_q3 AS complexity_q3,
  NULL AS quartile_label,
  NULL AS quartile_n,
  NULL AS quartile_mean_complexity,
  NULL AS top_los_threshold_hours,
  NULL AS top_los_n,
  NULL AS top_los_mortality_pct
FROM quartile_assign
CROSS JOIN thresholds t
GROUP BY t.complexity_q1, t.complexity_median, t.complexity_q3

UNION ALL

SELECT
  CONCAT('icu_flag=', CAST(icu_flag AS STRING)) AS group_label,
  COUNT(*) AS n_admissions,
  ROUND(AVG(complexity), 3) AS mean_complexity,
  MIN(complexity) AS min_complexity,
  MAX(complexity) AS max_complexity,
  ROUND(STDDEV_POP(complexity), 3) AS sd_complexity,
  ROUND(100.0 * SUM(qt_flag) / COUNT(*), 2) AS pct_with_qt_drug,
  ROUND(100.0 * SUM(bleed_flag) / COUNT(*), 2) AS pct_with_bleed_drug,
  NULL AS complexity_q1,
  NULL AS complexity_median,
  NULL AS complexity_q3,
  NULL AS quartile_label,
  NULL AS quartile_n,
  NULL AS quartile_mean_complexity,
  NULL AS top_los_threshold_hours,
  NULL AS top_los_n,
  NULL AS top_los_mortality_pct
FROM quartile_assign
GROUP BY icu_flag

UNION ALL

-- Mean complexity per quartile (quartile bins defined from overall thresholds)
SELECT
  'mean_complexity_by_quartile' AS group_label,
  NULL AS n_admissions,
  NULL AS mean_complexity,
  NULL AS min_complexity,
  NULL AS max_complexity,
  NULL AS sd_complexity,
  NULL AS pct_with_qt_drug,
  NULL AS pct_with_bleed_drug,
  NULL AS complexity_q1,
  NULL AS complexity_median,
  NULL AS complexity_q3,
  CAST(CONCAT('Q', complexity_quartile) AS STRING) AS quartile_label,
  COUNT(*) AS quartile_n,
  ROUND(AVG(complexity), 3) AS quartile_mean_complexity,
  NULL AS top_los_threshold_hours,
  NULL AS top_los_n,
  NULL AS top_los_mortality_pct
FROM quartile_assign
GROUP BY complexity_quartile

UNION ALL

-- Top-quartile LOS and mortality (using overall LOS Q3)
SELECT
  'top_quartile_los' AS group_label,
  NULL AS n_admissions,
  NULL AS mean_complexity,
  NULL AS min_complexity,
  NULL AS max_complexity,
  NULL AS sd_complexity,
  NULL AS pct_with_qt_drug,
  NULL AS pct_with_bleed_drug,
  NULL AS complexity_q1,
  NULL AS complexity_median,
  NULL AS complexity_q3,
  NULL AS quartile_label,
  NULL AS quartile_n,
  NULL AS quartile_mean_complexity,
  t.los_q3 AS top_los_threshold_hours,
  SUM(CASE WHEN pa.los_hours >= t.los_q3 THEN 1 ELSE 0 END) AS top_los_n,
  ROUND(100.0 * AVG(CASE WHEN pa.los_hours >= t.los_q3 THEN pa.hospital_expire_flag ELSE NULL END), 2) AS top_los_mortality_pct
FROM per_admission pa
CROSS JOIN thresholds t
GROUP BY t.los_q3

ORDER BY group_label;