WITH ards_cohort AS (
  -- Identify female patients aged 40-50 with primary ARDS diagnosis
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code = 'J80'
),

critical_labs AS (
  -- Define critical lab itemids (ARDS-relevant: renal, heme, WBC, blood gas)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category IN ('Chemistry', 'Hematology', 'Blood Gas', 'Urine')
    AND (
      label LIKE '%CREATININE%' OR  -- Renal
      label LIKE '%PLATELET%' OR    -- Heme
      label LIKE '%WBC%' OR         -- Infection/inflammation
      label LIKE '%PH%' OR          -- Acid-base
      label LIKE '%PAO2%'           -- Respiratory
    )
),

ards_scores AS (
  -- Compute instability score: count distinct abnormal critical lab TYPES in first 72h per hadm
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    ac.admittime,
    ac.hospital_expire_flag,
    ac.los_days,
    COUNT(DISTINCT 
      CASE 
        WHEN le.charttime >= ac.admittime 
          AND le.charttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 72 HOUR)
          AND le.valuenum IS NOT NULL
          AND le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper
        THEN le.itemid 
      END
    ) AS instability_score
  FROM ards_cohort ac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ac.subject_id = le.subject_id
    AND ac.hadm_id = le.hadm_id
  INNER JOIN critical_labs cl
    ON le.itemid = CAST(cl.itemid AS STRING)
  GROUP BY ac.subject_id, ac.hadm_id, ac.admittime, ac.hospital_expire_flag, ac.los_days
),

threshold_stats AS (
  -- Compute 75th percentile score
  SELECT 
    PERCENTILE_CONT(0.75) OVER () AS p75_score
  FROM ards_scores
),

high_risk_ards AS (
  -- ARDS patients at/above 75th percentile
  SELECT 
    ascore.*,
    ts.p75_score
  FROM ards_scores ascore
  CROSS JOIN threshold_stats ts
  WHERE ascore.instability_score >= ts.p75_score
),

non_ards_cohort AS (
  -- Age/gender-matched non-ARDS inpatients
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND EXTRACT(YEAR FROM a.admittime) = p.anchor_year
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id 
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code = 'J80'
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admission_type IN ('ELECTIVE', 'EMERGENCY', 'URGENT')
    AND d.hadm_id IS NULL  -- No ARDS
),

non_ards_scores AS (
  -- Compute mean critical lab events (instability score) for non-ARDS
  SELECT 
    nac.subject_id,
    nac.hadm_id,
    COUNT(DISTINCT 
      CASE 
        WHEN le.charttime >= nac.admittime 
          AND le.charttime <= TIMESTAMP_ADD(nac.admittime, INTERVAL 72 HOUR)
          AND le.valuenum IS NOT NULL
          AND le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper
        THEN le.itemid 
      END
    ) AS instability_score
  FROM non_ards_cohort nac
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON nac.subject_id = le.subject_id
    AND nac.hadm_id = le.hadm_id
  INNER JOIN critical_labs cl
    ON le.itemid = CAST(cl.itemid AS STRING)
  GROUP BY nac.subject_id, nac.hadm_id
)

-- Final summary: 75th percentile, high-risk ARDS stats, and non-ARDS comparison
SELECT 
  ts.p75_score AS p75_instability_score,
  AVG(CASE WHEN hra.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS high_score_mortality_rate,
  AVG(hra.los_days) AS high_score_mean_los_days,
  AVG(hra.instability_score) AS ards_high_mean_critical_events,
  (SELECT AVG(nas.instability_score) FROM non_ards_scores nas) AS non_ards_mean_critical_events
FROM threshold_stats ts
CROSS JOIN high_risk_ards hra;