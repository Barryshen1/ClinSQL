WITH patients_pe AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.icd_code IN ('I260', 'I269', 'I2699')  -- ICD-10 codes for PE (without decimal)
),

-- Elixhauser comorbidities (simplified set)
comorbidity_scores AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    SUM(
      CASE 
        WHEN d.long_title LIKE '%congestive heart failure%' THEN 1
        WHEN d.long_title LIKE '%cardiac arrhythmias%' THEN 1
        WHEN d.long_title LIKE '%valvular disease%' THEN 1
        WHEN d.long_title LIKE '%pulmonary circulation disorders%' AND d.icd_code NOT IN ('I260','I269','I2699') THEN 1  -- exclude PE itself
        WHEN d.long_title LIKE '%peripheral vascular disease%' THEN 1
        WHEN d.long_title LIKE '%hypertension%' THEN 1
        WHEN d.long_title LIKE '%renal failure%' THEN 1
        WHEN d.long_title LIKE '%diabetes%' THEN 1
        WHEN d.long_title LIKE '%liver disease%' THEN 1
        WHEN d.long_title LIKE '%lymphoma%' THEN 1
        WHEN d.long_title LIKE '%metastatic cancer%' THEN 1
        WHEN d.long_title LIKE '%solid tumor%' THEN 1
        WHEN d.long_title LIKE '%rheumatoid arthritis%' THEN 1
        WHEN d.long_title LIKE '%coagulopathy%' THEN 1
        WHEN d.long_title LIKE '%obesity%' THEN 1
        WHEN d.long_title LIKE '%weight loss%' THEN 1
        WHEN d.long_title LIKE '%fluid and electrolyte disorders%' THEN 1
        WHEN d.long_title LIKE '%blood loss anemia%' THEN 1
        WHEN d.long_title LIKE '%deficiency anemias%' THEN 1
        WHEN d.long_title LIKE '%alcohol abuse%' THEN 1
        WHEN d.long_title LIKE '%drug abuse%' THEN 1
        WHEN d.long_title LIKE '%psychoses%' THEN 1
        WHEN d.long_title LIKE '%depression%' THEN 1
        ELSE 0
      END
    ) AS elixhauser_score
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_pe pp ON a.subject_id = pp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime
),

-- 75th percentile of Elixhauser score in this cohort
percentile_threshold AS (
  SELECT APPROX_QUANTILES(elixhauser_score, 100)[OFFSET(75)] AS p75_score
  FROM comorbidity_scores
),

-- High comorbidity group: >75th percentile
high_comorb AS (
  SELECT cs.*
  FROM comorbidity_scores cs
  CROSS JOIN percentile_threshold pt
  WHERE cs.elixhauser_score > pt.p75_score
),

-- Outcomes: mortality, AKI, ARDS, LOS
outcomes AS (
  SELECT
    hc.subject_id,
    hc.hadm_id,
    hc.admittime,
    hc.dischtime,
    hc.deathtime,
    hc.elixhauser_score,
    CASE WHEN hc.deathtime IS NOT NULL AND DATETIME_DIFF(hc.deathtime, hc.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS died_within_90d,
    -- AKI diagnosis
    MAX(CASE WHEN d.long_title LIKE '%acute kidney%' OR d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    -- ARDS diagnosis
    MAX(CASE WHEN d.long_title LIKE '%acute respiratory distress%' OR d.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM high_comorb hc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON hc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY hc.subject_id, hc.hadm_id, hc.admittime, hc.dischtime, hc.deathtime, hc.elixhauser_score
),

-- Hospital and ICU LOS for survivors
survivors_los AS (
  SELECT
    o.subject_id,
    o.hadm_id,
    o.elixhauser_score,
    o.died_within_90d,
    o.has_aki,
    o.has_ards,
    DATETIME_DIFF(o.dischtime, o.admittime, HOUR) / 24.0 AS hosp_los_days,
    COALESCE(i.los, 0) AS icu_los_days
  FROM outcomes o
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON o.hadm_id = i.hadm_id
  WHERE o.died_within_90d = 0  -- survivors
),

-- Final summary
cohort_summary AS (
  SELECT
    AVG(elixhauser_score) AS mean_risk_score,
    AVG(CAST(died_within_90d AS FLOAT64)) AS mortality_90d_rate,
    AVG(CAST(has_aki AS FLOAT64)) AS aki_rate_survivors,
    AVG(CAST(has_ards AS FLOAT64)) AS ards_rate_survivors,
    AVG(hosp_los_days) AS mean_hosp_los_survivors,
    AVG(icu_los_days) AS mean_icu_los_survivors,
    (SELECT p75_score FROM percentile_threshold) AS risk_score_75th_percentile
  FROM survivors_los
)

SELECT * FROM cohort_summary;