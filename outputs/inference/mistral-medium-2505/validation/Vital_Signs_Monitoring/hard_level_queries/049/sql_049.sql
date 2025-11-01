WITH sepsis_patients AS (
  -- Identify male patients aged 78-88 with sepsis
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    i.los AS icu_los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND d.icd_code IN (
      '995.91', '995.92', '785.52',  -- ICD-9 codes for sepsis
      'R65.20', 'R65.21', 'A41.9'     -- ICD-10 codes for sepsis
    )
    AND i.intime >= a.admittime
),

-- Calculate instability score components in first 24 hours
vital_signs AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    -- Heart rate (itemid 220045)
    MAX(CASE WHEN itemid = 220045 THEN valuenum ELSE NULL END) AS max_heart_rate,
    MIN(CASE WHEN itemid = 220045 THEN valuenum ELSE NULL END) AS min_heart_rate,
    -- Systolic blood pressure (itemid 220050)
    MIN(CASE WHEN itemid = 220050 THEN valuenum ELSE NULL END) AS min_sbp,
    -- Respiratory rate (itemid 220210)
    MAX(CASE WHEN itemid = 220210 THEN valuenum ELSE NULL END) AS max_resp_rate,
    -- Temperature (itemid 223761)
    MAX(CASE WHEN itemid = 223761 THEN valuenum ELSE NULL END) AS max_temp,
    -- Oxygen saturation (itemid 220277)
    MIN(CASE WHEN itemid = 220277 THEN valuenum ELSE NULL END) AS min_spo2
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    sepsis_patients sp
    ON ce.subject_id = sp.subject_id AND ce.stay_id = sp.stay_id
  WHERE
    ce.charttime BETWEEN sp.icu_intime AND TIMESTAMP_ADD(sp.icu_intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220045, 220050, 220210, 223761, 220277)
  GROUP BY
    ce.subject_id, ce.stay_id
),

-- Calculate instability score (simplified example - adjust weights as needed)
instability_scores AS (
  SELECT
    subject_id,
    stay_id,
    -- Example score calculation (adjust based on clinical definition)
    (max_heart_rate - min_heart_rate) * 0.2 +
    (120 - min_sbp) * 0.3 +
    (max_resp_rate - 12) * 0.2 +
    (max_temp - 36.5) * 0.1 +
    (100 - min_spo2) * 0.2 AS instability_score
  FROM
    vital_signs
),

-- Get percentile rank for score of 85
percentile_rank AS (
  SELECT
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile,
    instability_score
  FROM
    instability_scores
  WHERE
    instability_score IS NOT NULL
),

-- Calculate quartiles and metrics for quartile 4
quartile_analysis AS (
  SELECT
    NTILE(4) OVER (ORDER BY instability_score) AS quartile,
    instability_score,
    icu_los,
    hospital_expire_flag
  FROM
    instability_scores isc
  JOIN
    sepsis_patients sp
    ON isc.subject_id = sp.subject_id AND isc.stay_id = sp.stay_id
  WHERE
    instability_score IS NOT NULL
)

-- Final results
SELECT
  -- Percentile rank for score of 85
  (SELECT percentile FROM percentile_rank WHERE instability_score = 85) AS percentile_rank_for_85,

  -- Mean ICU LOS for quartile 4
  (SELECT AVG(icu_los) FROM quartile_analysis WHERE quartile = 4) AS mean_icu_los_quartile4,

  -- Hospital mortality rate for quartile 4
  (SELECT AVG(CAST(hospital_expire_flag AS INT64)) FROM quartile_analysis WHERE quartile = 4) AS mortality_rate_quartile4;