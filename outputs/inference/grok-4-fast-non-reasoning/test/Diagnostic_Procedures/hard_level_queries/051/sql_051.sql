WITH cohort AS (
  -- Base ICU stays for male patients aged 90-100
  SELECT DISTINCT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.los,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (i.first_careunit LIKE '%ICU%' OR i.last_careunit LIKE '%ICU%')
),
sepsis_cohort AS (
  -- Filter to sepsis cases
  SELECT 
    c.*,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
          ON d.icd_code = icd.icd_code 
          AND d.icd_version = icd.icd_version
        WHERE d.subject_id = c.subject_id 
          AND d.hadm_id = c.hadm_id
          AND (
            (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'A41%') OR
            (d.icd_version = 'ICD-9' AND (d.icd_code LIKE '038%' OR d.icd_code = '99591'))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_sepsis
  FROM cohort c
),
total_icu_stays AS (
  -- Total ICU stays for male 90-100 (no sepsis filter)
  SELECT COUNT(DISTINCT stay_id) AS total_stays
  FROM cohort
),
utilization AS (
  -- Diagnostic events in first 24h per stay (only for sepsis cohort)
  SELECT 
    sc.stay_id,
    (COALESCE(SUM(num_labs), 0) + 
     COALESCE(SUM(num_micro), 0) + 
     COALESCE(SUM(num_chartevents), 0)) AS diag_count
  FROM sepsis_cohort sc
  WHERE sc.has_sepsis = 1
  -- First 24h window
  LEFT JOIN (
    SELECT 
      le.subject_id, 
      le.hadm_id, 
      COUNT(DISTINCT le.labevent_id) AS num_labs
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    WHERE le.valuenum IS NOT NULL
    GROUP BY le.subject_id, le.hadm_id
  ) le
    ON le.subject_id = sc.subject_id 
    AND le.hadm_id = sc.hadm_id
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2
      WHERE le2.subject_id = sc.subject_id 
        AND le2.hadm_id = sc.hadm_id
        AND le2.charttime >= sc.intime 
        AND le2.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
        AND le2.valuenum IS NOT NULL
    )
  LEFT JOIN (
    SELECT 
      me.subject_id, 
      me.hadm_id, 
      COUNT(DISTINCT me.microevent_id) AS num_micro
    FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
    GROUP BY me.subject_id, me.hadm_id
  ) me
    ON me.subject_id = sc.subject_id 
    AND me.hadm_id = sc.hadm_id
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me2
      WHERE me2.subject_id = sc.subject_id 
        AND me2.hadm_id = sc.hadm_id
        AND me2.charttime >= sc.intime 
        AND me2.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
    )
  LEFT JOIN (
    SELECT 
      ce.subject_id, 
      ce.stay_id, 
      COUNT(DISTINCT ce.itemid) AS num_chartevents  -- Count unique itemids as proxy for diagnostic types
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
      ON ce.itemid = di.itemid
    WHERE ce.valuenum IS NOT NULL
      AND di.category IN ('Vital Signs', 'Routine Vital Signs', 'Laboratory', 'Blood Gases', 'Urine Tests', 'Procedures')
    GROUP BY ce.subject_id, ce.stay_id
  ) ce
    ON ce.subject_id = sc.subject_id 
    AND ce.stay_id = sc.stay_id
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2
      WHERE ce2.subject_id = sc.subject_id 
        AND ce2.stay_id = sc.stay_id
        AND ce2.charttime >= sc.intime 
        AND ce2.charttime <= TIMESTAMP_ADD(sc.intime, INTERVAL 24 HOUR)
        AND ce2.valuenum IS NOT NULL
    )
  GROUP BY sc.stay_id
),
mortality AS (
  -- Mortality per stay
  SELECT 
    sc.stay_id,
    CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END AS mortality_flag
  FROM sepsis_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON sc.hadm_id = a.hadm_id
  WHERE sc.has_sepsis = 1
)
-- Final aggregation
SELECT 
  STDDEV(diag_count) AS sd_diagnostic_utilization,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
  APPROX_QUANTILES(diag_count, 100)[OFFSET(95)] AS p95_diagnostic_utilization,
  (SUM(m.mortality_flag) * 100.0 / COUNT(DISTINCT u.stay_id)) AS in_hospital_mortality_pct,
  AVG(sc.los) AS avg_los_days,
  COUNT(DISTINCT u.stay_id) AS cohort_icu_stays,
  t.total_stays AS total_icu_stays_male_90_100
FROM utilization u
INNER JOIN sepsis_cohort sc ON u.stay_id = sc.stay_id AND sc.has_sepsis = 1
LEFT JOIN mortality m ON u.stay_id = m.stay_id
CROSS JOIN total_icu_stays t;