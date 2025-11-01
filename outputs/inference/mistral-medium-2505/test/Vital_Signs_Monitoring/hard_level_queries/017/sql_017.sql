WITH
-- Define asthma ICD codes (ICD-9 and ICD-10)
asthma_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%asthma%'
),

-- Get female patients aged 83-93
eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    -- Calculate time difference between ICU admission and hospital discharge
    TIMESTAMP_DIFF(a.dischtime, i.intime, HOUR) AS hours_to_discharge,
    -- Check if patient has asthma diagnosis
    MAX(CASE WHEN d.icd_code IN (SELECT icd_code FROM asthma_codes) THEN 1 ELSE 0 END) AS has_asthma
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hospital_expire_flag IS NOT NULL
  GROUP BY
    p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime,
    a.hospital_expire_flag, i.stay_id, i.intime, i.outtime, i.los
),

-- Calculate instability score components (simplified example)
instability_components AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    ce.charttime,
    -- Heart rate (itemid 220045)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS heart_rate,
    -- Respiratory rate (itemid 220210)
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) AS respiratory_rate,
    -- Systolic blood pressure (itemid 220050)
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum ELSE NULL END) AS sbp,
    -- Diastolic blood pressure (itemid 220051)
    MAX(CASE WHEN ce.itemid = 220051 THEN ce.valuenum ELSE NULL END) AS dbp,
    -- Oxygen saturation (itemid 220277)
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS spo2,
    -- Temperature (itemid 223761)
    MAX(CASE WHEN ce.itemid = 223761 THEN ce.valuenum ELSE NULL END) AS temperature
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON e.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN e.icu_intime AND TIMESTAMP_ADD(e.icu_intime, INTERVAL 72 HOUR)
    AND ce.itemid IN (220045, 220210, 220050, 220051, 220277, 223761)
  GROUP BY
    e.subject_id, e.hadm_id, e.stay_id, ce.charttime
),

-- Calculate instability score (simplified example)
instability_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    -- Simplified instability score calculation (adjust weights as needed)
    (COALESCE(heart_rate, 0) * 0.1) +
    (COALESCE(respiratory_rate, 0) * 0.2) +
    (CASE WHEN COALESCE(sbp, 0) < 90 THEN 1 ELSE 0 END * 0.3) +
    (CASE WHEN COALESCE(spo2, 0) < 90 THEN 1 ELSE 0 END * 0.4) +
    (CASE WHEN COALESCE(temperature, 0) > 38 THEN 1 ELSE 0 END * 0.2) AS instability_score
  FROM instability_components
),

-- Calculate percentiles for each group
score_percentiles AS (
  SELECT
    has_asthma,
    PERCENTILE_CONT(instability_score, 0.25) OVER(PARTITION BY has_asthma) AS p25_instability_score,
    PERCENTILE_CONT(instability_score, 0.5) OVER(PARTITION BY has_asthma) AS p50_instability_score,
    PERCENTILE_CONT(instability_score, 0.75) OVER(PARTITION BY has_asthma) AS p75_instability_score,
    PERCENTILE_CONT(instability_score, 0.95) OVER(PARTITION BY has_asthma) AS p95_instability_score
  FROM (
    SELECT
      e.has_asthma,
      i.instability_score
    FROM eligible_patients e
    JOIN instability_scores i ON e.stay_id = i.stay_id
    WHERE i.instability_score IS NOT NULL
  )
  GROUP BY has_asthma, instability_score
),

-- Aggregate scores for each patient
patient_scores AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.stay_id,
    e.has_asthma,
    e.icu_los,
    e.hospital_expire_flag,
    AVG(i.instability_score) AS avg_instability_score,
    STDDEV(i.instability_score) AS stddev_instability_score,
    p.p25_instability_score,
    p.p50_instability_score,
    p.p75_instability_score,
    p.p95_instability_score
  FROM eligible_patients e
  JOIN instability_scores i ON e.stay_id = i.stay_id
  JOIN (
    SELECT
      has_asthma,
      MAX(p25_instability_score) AS p25_instability_score,
      MAX(p50_instability_score) AS p50_instability_score,
      MAX(p75_instability_score) AS p75_instability_score,
      MAX(p95_instability_score) AS p95_instability_score
    FROM score_percentiles
    GROUP BY has_asthma
  ) p ON e.has_asthma = p.has_asthma
  GROUP BY
    e.subject_id, e.hadm_id, e.stay_id, e.has_asthma, e.icu_los, e.hospital_expire_flag,
    p.p25_instability_score, p.p50_instability_score, p.p75_instability_score, p.p95_instability_score
)

-- Final comparison between asthma and non-asthma cohorts
SELECT
  has_asthma,
  COUNT(*) AS patient_count,
  AVG(avg_instability_score) AS mean_instability_score,
  AVG(stddev_instability_score) AS mean_stddev_instability_score,
  AVG(p25_instability_score) AS mean_p25_instability_score,
  AVG(p50_instability_score) AS mean_p50_instability_score,
  AVG(p75_instability_score) AS mean_p75_instability_score,
  AVG(p95_instability_score) AS mean_p95_instability_score,
  AVG(icu_los) AS mean_icu_los,
  SUM(hospital_expire_flag) AS mortality_count,
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM patient_scores
GROUP BY has_asthma
ORDER BY has_asthma;