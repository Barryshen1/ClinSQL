WITH cohort AS (
  SELECT 
    pat.subject_id,
    pat.gender,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag AS mortality,
    -- Calculate age at ICU admission
    pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) AS age_at_icu_adm
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE pat.gender = 'M'
    -- Age 63-73 at ICU admission
    AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) BETWEEN 63 AND 73
    -- Post-op: has at least one ICD procedure
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
      WHERE proc.hadm_id = icu.hadm_id
    )
),

-- Instability score components (first 24 hours)
temp_score AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid IN (223761, 223762) AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS temp_point
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (223761, 223762)  -- Temperature in Celsius
  GROUP BY c.stay_id
),

spo2_score AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid IN (220277, 220227) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_point
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220277, 220227)  -- SpO2
  GROUP BY c.stay_id
),

rr_score AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid IN (220210, 224688, 224689, 224690) AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_point
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220210, 224688, 224689, 224690)  -- Respiratory Rate
  GROUP BY c.stay_id
),

sbp_score AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid IN (220050, 225309) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_point
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220050, 225309)  -- Systolic BP
  GROUP BY c.stay_id
),

hr_score AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN ce.itemid = 220045 AND ce.valuenum > 120 THEN 1 ELSE 0 END) AS hr_point
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.itemid = 220045  -- Heart Rate
  GROUP BY c.stay_id
),

instability_scores AS (
  SELECT 
    c.stay_id,
    COALESCE(t.temp_point, 0) 
      + COALESCE(s.spo2_point, 0) 
      + COALESCE(r.rr_point, 0) 
      + COALESCE(sb.sbp_point, 0) 
      + COALESCE(h.hr_point, 0) AS instability_score
  FROM cohort c
  LEFT JOIN temp_score t ON c.stay_id = t.stay_id
  LEFT JOIN spo2_score s ON c.stay_id = s.stay_id
  LEFT JOIN rr_score r ON c.stay_id = r.stay_id
  LEFT JOIN sbp_score sb ON c.stay_id = sb.stay_id
  LEFT JOIN hr_score h ON c.stay_id = h.stay_id
),

-- Compute 75th percentile for instability score
q3_value AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[SAFE_OFFSET(75)] AS q3_score
  FROM instability_scores
),

cohort_with_scores AS (
  SELECT 
    c.*,
    i.instability_score,
    q3.q3_score
  FROM cohort c
  INNER JOIN instability_scores i
    ON c.stay_id = i.stay_id
  CROSS JOIN q3_value q3
),

cohort_groups AS (
  SELECT 
    *,
    CASE 
      WHEN instability_score >= q3_score THEN 'high' 
      ELSE 'low' 
    END AS instability_group
  FROM cohort_with_scores
),

-- Outcomes (entire ICU stay) - combined for efficiency
all_events AS (
  SELECT 
    cg.stay_id,
    cg.instability_group,
    cg.icu_los,
    cg.mortality,
    MAX(CASE WHEN ce.itemid IN (223761, 223762) AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever,
    MAX(CASE WHEN ce.itemid IN (220277, 220227) AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low,
    MAX(CASE WHEN ce.itemid IN (220210, 224688, 224689, 224690) AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS rr_high
  FROM cohort_groups cg
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cg.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN cg.intime AND cg.outtime
    AND (
      ce.itemid IN (223761, 223762) OR  -- Temperature
      ce.itemid IN (220277, 220227) OR  -- SpO2
      ce.itemid IN (220210, 224688, 224689, 224690)  -- Respiratory Rate
    )
  GROUP BY cg.stay_id, cg.instability_group, cg.icu_los, cg.mortality
),

-- Compute 95th percentile for instability score
percentile_95 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[SAFE_OFFSET(95)] AS p95
  FROM instability_scores
)

-- Final output: 95th percentile & group comparisons
SELECT 
  '95th_percentile_instability_score' AS metric,
  (SELECT p95 FROM percentile_95) AS value,
  NULL AS instability_group,
  NULL AS n_stays,
  NULL AS fever_percent,
  NULL AS spo2_low_percent,
  NULL AS rr_high_percent,
  NULL AS median_los,
  NULL AS mortality_percent
UNION ALL
SELECT 
  'group_comparison' AS metric,
  NULL AS value,
  instability_group,
  COUNT(*) AS n_stays,
  ROUND(AVG(fever) * 100, 1) AS fever_percent,
  ROUND(AVG(spo2_low) * 100, 1) AS spo2_low_percent,
  ROUND(AVG(rr_high) * 100, 1) AS rr_high_percent,
  ROUND(APPROX_QUANTILES(icu_los, 100)[SAFE_OFFSET(50)], 1) AS median_los,
  ROUND(AVG(mortality) * 100, 1) AS mortality_percent
FROM all_events
GROUP BY instability_group;