WITH cohort AS (
  -- Base cohort: males 48-58 with pneumonia diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '480%' OR diag.icd_code LIKE '481%' OR
        diag.icd_code LIKE '482%' OR diag.icd_code LIKE '483%' OR
        diag.icd_code LIKE '484%' OR diag.icd_code LIKE '485%' OR
        diag.icd_code LIKE '486%'
      ))
      OR (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'J12%' OR diag.icd_code LIKE 'J13%' OR
        diag.icd_code LIKE 'J14%' OR diag.icd_code LIKE 'J15%' OR
        diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' OR
        diag.icd_code LIKE 'J18%'
      ))
    )
),

med_events AS (
  -- EMAR events in first 24h of admission
  SELECT
    c.*,
    e.medication,
    e.charttime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
  WHERE e.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
    AND e.medication IS NOT NULL
),

complexity AS (
  -- Overall med complexity per hadm_id
  SELECT
    hadm_id,
    COUNT(DISTINCT medication) AS med_complexity
  FROM med_events
  GROUP BY hadm_id
  HAVING med_complexity > 0
),

serotonergic_events AS (
  -- Serotonergic meds in first 24h
  SELECT
    hadm_id,
    COUNT(DISTINCT medication) AS serotonergic_count
  FROM med_events
  WHERE LOWER(medication) LIKE '%sertraline%'
     OR LOWER(medication) LIKE '%fluoxetine%'
     OR LOWER(medication) LIKE '%citalopram%'
     OR LOWER(medication) LIKE '%escitalopram%'
     OR LOWER(medication) LIKE '%paroxetine%'
     OR LOWER(medication) LIKE '%fluvoxamine%'
     OR LOWER(medication) LIKE '%venlafaxine%'
     OR LOWER(medication) LIKE '%duloxetine%'
     OR LOWER(medication) LIKE '%tramadol%'
     OR LOWER(medication) LIKE '%ondansetron%'
  GROUP BY hadm_id
),

patients_with_meds AS (
  -- Main table: cohort with meds, flags for risk and ICU
  SELECT
    c.*,
    cpl.med_complexity,
    COALESCE(s.serotonergic_count, 0) AS serotonergic_count,
    CASE WHEN i.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_icu
  FROM cohort c
  INNER JOIN complexity cpl ON c.hadm_id = cpl.hadm_id
  LEFT JOIN serotonergic_events s ON c.hadm_id = s.hadm_id
  LEFT JOIN (
    SELECT DISTINCT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),

-- Complexity distribution
complexity_stats AS (
  SELECT
    'mean_complexity' AS metric,
    CAST(AVG(med_complexity) AS FLOAT64) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds
  UNION ALL
  SELECT
    'p25_complexity' AS metric,
    NULL AS value,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(1)] AS p25,
    NULL AS p50, NULL AS p75
  FROM patients_with_meds
  UNION ALL
  SELECT
    'p50_complexity' AS metric,
    NULL AS value,
    NULL AS p25,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(2)] AS p50,
    NULL AS p75
  FROM patients_with_meds
  UNION ALL
  SELECT
    'p75_complexity' AS metric,
    NULL AS value,
    NULL AS p25, NULL AS p50,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(3)] AS p75
  FROM patients_with_meds
),

-- Risk group stats (serotonergic_count >= 2)
risk_stats AS (
  SELECT
    'risk_los_mean' AS metric,
    CAST(AVG(los_days) AS FLOAT64) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds
  WHERE serotonergic_count >= 2
  UNION ALL
  SELECT
    'risk_mortality_rate' AS metric,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds
  WHERE serotonergic_count >= 2
),

-- ICU group stats
icu_stats AS (
  SELECT
    'icu_los_mean' AS metric,
    CAST(AVG(los_days) AS FLOAT64) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds
  WHERE is_icu = 1
  UNION ALL
  SELECT
    'icu_mortality_rate' AS metric,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds
  WHERE is_icu = 1
),

-- Top-quartile for risk group
risk_p75 AS (
  SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los
  FROM patients_with_meds
  WHERE serotonergic_count >= 2
),
risk_topq_stats AS (
  SELECT
    'risk_topq_los' AS metric,
    CAST(r.p75_los AS FLOAT64) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM risk_p75 r
  UNION ALL
  SELECT
    'risk_topq_mortality' AS metric,
    AVG(CAST(pwm.hospital_expire_flag AS FLOAT64)) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds pwm
  CROSS JOIN risk_p75 r
  WHERE pwm.serotonergic_count >= 2 AND pwm.los_days >= r.p75_los
),

-- Top-quartile for ICU group
icu_p75 AS (
  SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS p75_los
  FROM patients_with_meds
  WHERE is_icu = 1
),
icu_topq_stats AS (
  SELECT
    'icu_topq_los' AS metric,
    CAST(i.p75_los AS FLOAT64) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM icu_p75 i
  UNION ALL
  SELECT
    'icu_topq_mortality' AS metric,
    AVG(CAST(pwm.hospital_expire_flag AS FLOAT64)) AS value,
    NULL AS p25, NULL AS p50, NULL AS p75
  FROM patients_with_meds pwm
  CROSS JOIN icu_p75 i
  WHERE pwm.is_icu = 1 AND pwm.los_days >= i.p75_los
)

-- Combine all metrics
SELECT * FROM complexity_stats
UNION ALL SELECT * FROM risk_stats
UNION ALL SELECT * FROM icu_stats
UNION ALL SELECT * FROM risk_topq_stats
UNION ALL SELECT * FROM icu_topq_stats
ORDER BY metric;