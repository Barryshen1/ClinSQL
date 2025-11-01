WITH base_cohort AS (
  -- Male patients aged 45-55 with first ICU stay and ARF
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.icd_version = 10
    AND d.icd_code LIKE 'N17%'
    AND d.seq_num = 1
    AND i.los >= 2  -- At least 48 hours
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
),

matched_cohort AS (
  -- All male 45-55 ICU patients (first stay, no ARF filter)
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND i.los >= 2
  QUALIFY ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
),

instability_flags AS (
  -- Flags for each component in first 48h (for ARF cohort)
  SELECT 
    bc.*,
    -- Tachycardia: any HR > 100
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = bc.subject_id
        AND ce.hadm_id = bc.hadm_id
        AND ce.stay_id = bc.stay_id
        AND ce.itemid = 220045  -- Heart rate
        AND ce.valuenum > 100
        AND ce.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS flag_tachycardia,
    
    -- Hypotension: any MAP < 65
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = bc.subject_id
        AND ce.hadm_id = bc.hadm_id
        AND ce.stay_id = bc.stay_id
        AND ce.itemid = 220052  -- MAP
        AND ce.valuenum < 65
        AND ce.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS flag_hypotension,
    
    -- Hypoxemia: any SpO2 < 90
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.subject_id = bc.subject_id
        AND ce.hadm_id = bc.hadm_id
        AND ce.stay_id = bc.stay_id
        AND ce.itemid = 220277  -- SpO2
        AND ce.valuenum < 90
        AND ce.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS flag_hypoxemia,
    
    -- Oliguria: total urine < 4200 mL over 48h (35 mL/h avg for ~70kg)
    CASE WHEN (
      SELECT SUM(oe.value) FROM `physionet-data.mimiciv_3_1_icu.outputevents` oe
      WHERE oe.subject_id = bc.subject_id
        AND oe.hadm_id = bc.hadm_id
        AND oe.stay_id = bc.stay_id
        AND oe.itemid = 40055  -- Urine
        AND oe.valueuom = 'ml'
        AND oe.value > 0
        AND oe.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) < 4200 THEN 1 ELSE 0 END AS flag_oliguria,
    
    -- Acidosis: any pH < 7.35
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.subject_id = bc.subject_id
        AND le.hadm_id = bc.hadm_id
        AND le.itemid = 50820  -- Arterial pH
        AND le.valuenum < 7.35
        AND le.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS flag_acidosis,
    
    -- Hyperlactatemia: any lactate > 2
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.subject_id = bc.subject_id
        AND le.hadm_id = bc.hadm_id
        AND le.itemid = 50813  -- Lactate
        AND le.valuenum > 2
        AND le.charttime BETWEEN bc.intime AND TIMESTAMP_ADD(bc.intime, INTERVAL 48 HOUR)
    ) THEN 1 ELSE 0 END AS flag_lactate
  FROM base_cohort bc
),

scores AS (
  SELECT 
    *,
    (flag_tachycardia + flag_hypotension + flag_hypoxemia + flag_oliguria + flag_acidosis + flag_lactate) AS instability_score
  FROM instability_flags
),

percentiles AS (
  SELECT 
    PERCENTILE_CONT(0.95, instability_score) OVER () AS p95_score
  FROM scores
),

top_quartile AS (
  SELECT s.*
  FROM scores s
  CROSS JOIN (
    SELECT PERCENTILE_CONT(0.75, instability_score) OVER () AS q75_score
    FROM scores
  ) p
  WHERE s.instability_score > p.q75_score
),

-- Hypotension % time for top quartile (avg % across patients)
hypotension_pct_top AS (
  SELECT 
    AVG(hypotension_frac) AS avg_hypotension_pct
  FROM (
    SELECT 
      tq.subject_id,
      SAFE_DIVIDE(COUNTIF(ce.valuenum < 65), COUNT(ce.itemid)) AS hypotension_frac
    FROM top_quartile tq
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON tq.subject_id = ce.subject_id 
      AND tq.hadm_id = ce.hadm_id 
      AND tq.stay_id = ce.stay_id
    WHERE ce.itemid = 220052
      AND ce.charttime BETWEEN tq.intime AND TIMESTAMP_ADD(tq.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
    GROUP BY tq.subject_id
  )
),

-- Similar for tachycardia % time
tachycardia_pct_top AS (
  SELECT 
    AVG(tachycardia_frac) AS avg_tachycardia_pct
  FROM (
    SELECT 
      tq.subject_id,
      SAFE_DIVIDE(COUNTIF(ce.valuenum > 100), COUNT(ce.itemid)) AS tachycardia_frac
    FROM top_quartile tq
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
      ON tq.subject_id = ce.subject_id 
      AND tq.hadm_id = ce.hadm_id 
      AND tq.stay_id = ce.stay_id
    WHERE ce.itemid = 220045
      AND ce.charttime BETWEEN tq.intime AND TIMESTAMP_ADD(tq.intime, INTERVAL 48 HOUR)
      AND ce.valuenum IS NOT NULL
    GROUP BY tq.subject_id
  )
),

-- Aggregates for top quartile
top_agg AS (
  SELECT 
    'Top Quartile (ARF)' AS cohort,
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT)) * 100 AS mortality_pct,
    (SELECT avg_hypotension_pct * 100 FROM hypotension_pct_top) AS hypotension_pct,
    (SELECT avg_tachycardia_pct * 100 FROM tachycardia_pct_top) AS tachycardia_pct
  FROM top_quartile
),

-- Pre-aggregate fractions for matched cohort
matched_fractions AS (
  SELECT 
    m.subject_id,
    SAFE_DIVIDE(COUNTIF(ce_map.valuenum < 65), COUNT(ce_map.itemid)) AS hypotension_frac,
    SAFE_DIVIDE(COUNTIF(ce_hr.valuenum > 100), COUNT(ce_hr.itemid)) AS tachycardia_frac
  FROM matched_cohort m
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce_map
    ON m.subject_id = ce_map.subject_id 
    AND m.hadm_id = ce_map.hadm_id 
    AND m.stay_id = ce_map.stay_id
    AND ce_map.itemid = 220052
    AND ce_map.charttime BETWEEN m.intime AND TIMESTAMP_ADD(m.intime, INTERVAL 48 HOUR)
    AND ce_map.valuenum IS NOT NULL
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce_hr
    ON m.subject_id = ce_hr.subject_id 
    AND m.hadm_id = ce_hr.hadm_id 
    AND m.stay_id = ce_hr.stay_id
    AND ce_hr.itemid = 220045
    AND ce_hr.charttime BETWEEN m.intime AND TIMESTAMP_ADD(m.intime, INTERVAL 48 HOUR)
    AND ce_hr.valuenum IS NOT NULL
  GROUP BY m.subject_id
),

-- Aggregates for matched cohort
matched_agg AS (
  SELECT 
    'Age-Matched Cohort' AS cohort,
    AVG(m.los) AS avg_icu_los,
    AVG(CAST(m.hospital_expire_flag AS FLOAT)) * 100 AS mortality_pct,
    AVG(mf.hypotension_frac) * 100 AS hypotension_pct,
    AVG(mf.tachycardia_frac) * 100 AS tachycardia_pct
  FROM matched_cohort m
  INNER JOIN matched_fractions mf ON m.subject_id = mf.subject_id
)

-- Final results
SELECT '95th Percentile Instability Score (ARF Cohort)' AS metric, 
       CAST(p.p95_score AS STRING) AS value
FROM percentiles p

UNION ALL

SELECT cohort || ' - ICU LOS' AS metric, 
       CAST(avg_icu_los AS STRING) AS value
FROM top_agg

UNION ALL

SELECT cohort || ' - Mortality %' AS metric, 
       CAST(mortality_pct AS STRING) AS value
FROM top_agg

UNION ALL

SELECT cohort || ' - Hypotension % Time' AS metric, 
       CAST(hypotension_pct AS STRING) AS value
FROM top_agg

UNION ALL

SELECT cohort || ' - Tachycardia % Time' AS metric, 
       CAST(tachycardia_pct AS STRING) AS value
FROM top_agg

UNION ALL

SELECT cohort || ' - ICU LOS' AS metric, 
       CAST(avg_icu_los AS STRING) AS value
FROM matched_agg

UNION ALL

SELECT cohort || ' - Mortality %' AS metric, 
       CAST(mortality_pct AS STRING) AS value
FROM matched_agg

UNION ALL

SELECT cohort || ' - Hypotension % Time' AS metric, 
       CAST(hypotension_pct AS STRING) AS value
FROM matched_agg

UNION ALL

SELECT cohort || ' - Tachycardia % Time' AS metric, 
       CAST(tachycardia_pct AS STRING) AS value
FROM matched_agg

ORDER BY metric;