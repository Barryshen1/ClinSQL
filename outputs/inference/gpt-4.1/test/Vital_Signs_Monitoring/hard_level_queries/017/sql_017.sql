WITH vital_signs AS (
  SELECT itemid, LOWER(label) AS label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('heart rate', 'systolic blood pressure', 'respiratory rate', 'spo2', 'temperature')
),

-- Step 2: Asthma ICD codes
asthma_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%asthma%'
),

-- Step 3: ICU stays for females aged 83-93
icu_patients AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    CASE WHEN ah.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_asthma
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  LEFT JOIN asthma_hadm ah ON i.hadm_id = ah.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

-- Step 4: Instability score per ICU stay (first 72h)
instability_events AS (
  SELECT
    c.stay_id,
    c.charttime,
    v.label,
    c.valuenum,
    -- Abnormal flags
    CASE
      WHEN v.label = 'heart rate' AND (c.valuenum > 100 OR c.valuenum < 50) THEN 1
      WHEN v.label = 'systolic blood pressure' AND c.valuenum < 90 THEN 1
      WHEN v.label = 'respiratory rate' AND (c.valuenum > 20 OR c.valuenum < 10) THEN 1
      WHEN v.label = 'spo2' AND c.valuenum < 92 THEN 1
      WHEN v.label = 'temperature' AND (c.valuenum < 36 OR c.valuenum > 38) THEN 1
      ELSE 0
    END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN vital_signs v ON c.itemid = v.itemid
  JOIN icu_patients ip ON c.stay_id = ip.stay_id
  WHERE c.charttime BETWEEN ip.intime AND DATETIME_ADD(ip.intime, INTERVAL 72 HOUR)
    AND c.valuenum IS NOT NULL
),

instability_score AS (
  SELECT
    ip.subject_id,
    ip.hadm_id,
    ip.stay_id,
    ip.anchor_age,
    ip.gender,
    ip.los,
    ip.hospital_expire_flag,
    ip.has_asthma,
    SUM(e.is_abnormal) AS instability_score
  FROM icu_patients ip
  LEFT JOIN instability_events e ON ip.stay_id = e.stay_id
  GROUP BY ip.subject_id, ip.hadm_id, ip.stay_id, ip.anchor_age, ip.gender, ip.los, ip.hospital_expire_flag, ip.has_asthma
),

-- Step 5: Summary stats for asthma cohort
asthma_stats AS (
  SELECT
    'Asthma cohort' AS cohort,
    COUNT(*) AS n_stays,
    AVG(s.instability_score) AS mean_instability_score,
    STDDEV(s.instability_score) AS sd_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(25)] AS p25_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(50)] AS p50_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(75)] AS p75_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(95)] AS p95_instability_score,
    AVG(s.los) AS mean_icu_los,
    SUM(CAST(s.hospital_expire_flag AS INT64))/COUNT(*) AS mortality_rate
  FROM instability_score s
  WHERE s.has_asthma = 1
),

-- Step 6: Summary stats for age-matched cohort
age_matched_stats AS (
  SELECT
    'Age-matched cohort' AS cohort,
    COUNT(*) AS n_stays,
    AVG(s.instability_score) AS mean_instability_score,
    STDDEV(s.instability_score) AS sd_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(25)] AS p25_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(50)] AS p50_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(75)] AS p75_instability_score,
    APPROX_QUANTILES(s.instability_score, 100)[OFFSET(95)] AS p95_instability_score,
    AVG(s.los) AS mean_icu_los,
    SUM(CAST(s.hospital_expire_flag AS INT64))/COUNT(*) AS mortality_rate
  FROM instability_score s
)

-- Final output: compare cohorts
SELECT * FROM asthma_stats
UNION ALL
SELECT * FROM age_matched_stats
ORDER BY cohort DESC;