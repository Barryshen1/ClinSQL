WITH patients_age AS (
  SELECT 
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM DATETIME(icu.intime)) - p.anchor_year + p.anchor_age AS age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM DATETIME(icu.intime)) - p.anchor_year + p.anchor_age BETWEEN 55 AND 65
),

cohort AS (
  SELECT 
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    pa.age_at_icu_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN patients_age pa ON icu.subject_id = pa.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
),

-- Identify patients who received HFNC within 24 hours of ICU admission
hfnc_exposure AS (
  SELECT DISTINCT
    c.stay_id,
    TRUE AS received_hfnc_24h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label = 'O2 Delivery Device'
    AND ce.value IS NOT NULL
    AND LOWER(ce.value) LIKE '%high flow%'
),

-- Extract heart rate and systolic blood pressure measurements during ICU stay
vitals AS (
  SELECT
    c.stay_id,
    di.label,
    ce.valuenum,
    ce.charttime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON c.stay_id = ce.stay_id
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.outtime
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label IN ('Heart Rate', 'Arterial Blood Pressure systolic')
    AND ce.valuenum IS NOT NULL
),

-- Compute tachycardia and hypotension burden per patient
vital_stats AS (
  SELECT
    stay_id,
    AVG(CASE WHEN label = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END) AS prop_tachycardia,
    AVG(CASE WHEN label = 'Arterial Blood Pressure systolic' AND valuenum < 90 THEN 1 ELSE 0 END) AS prop_hypotension
  FROM vitals
  GROUP BY stay_id
),

-- Combine all data
summary AS (
  SELECT
    c.stay_id,
    COALESCE(h.received_hfnc_24h, FALSE) AS hfnc_group,
    vs.prop_tachycardia,
    vs.prop_hypotension,
    c.icu_los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN hfnc_exposure h ON c.stay_id = h.stay_id
  LEFT JOIN vital_stats vs ON c.stay_id = vs.stay_id
)

-- Final aggregation by HFNC group using APPROX_QUANTILES
SELECT
  hfnc_group,
  -- Extract median, p25, p75, p95 using APPROX_QUANTILES
  APPROX_QUANTILES(prop_tachycardia, 1000)[OFFSET(250)] AS tachycardia_burden_p25,
  APPROX_QUANTILES(prop_tachycardia, 1000)[OFFSET(500)] AS tachycardia_burden_median,
  APPROX_QUANTILES(prop_tachycardia, 1000)[OFFSET(750)] AS tachycardia_burden_p75,
  APPROX_QUANTILES(prop_tachycardia, 1000)[OFFSET(950)] AS tachycardia_burden_p95,
  APPROX_QUANTILES(prop_hypotension, 1000)[OFFSET(250)] AS hypotension_burden_p25,
  APPROX_QUANTILES(prop_hypotension, 1000)[OFFSET(500)] AS hypotension_burden_median,
  APPROX_QUANTILES(prop_hypotension, 1000)[OFFSET(750)] AS hypotension_burden_p75,
  APPROX_QUANTILES(prop_hypotension, 1000)[OFFSET(950)] AS hypotension_burden_p95,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(250)] AS icu_los_p25,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(500)] AS icu_los_median,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(750)] AS icu_los_p75,
  APPROX_QUANTILES(icu_los, 1000)[OFFSET(950)] AS icu_los_p95,
  AVG(hospital_expire_flag) AS mortality_rate
FROM summary
GROUP BY hfnc_group
ORDER BY hfnc_group;