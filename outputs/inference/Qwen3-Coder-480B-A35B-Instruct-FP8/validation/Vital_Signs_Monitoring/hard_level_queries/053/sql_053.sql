WITH shock_patients AS (
  -- Identify patients with a shock diagnosis
  SELECT DISTINCT di.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%shock%'
),
filtered_patients AS (
  -- Filter female patients aged 59–69
  SELECT p.subject_id, p.gender, p.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
),
eligible_icu_stays AS (
  -- Get ICU stays for filtered patients
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN filtered_patients fp ON i.subject_id = fp.subject_id
),
shock_flag AS (
  -- Flag ICU stays with shock diagnosis
  SELECT eis.stay_id,
         CASE WHEN sp.subject_id IS NOT NULL THEN 1 ELSE 0 END AS shock
  FROM eligible_icu_stays eis
  LEFT JOIN shock_patients sp ON eis.subject_id = sp.subject_id
),
vitals AS (
  -- Extract vital signs in first 24 hours
  SELECT
    ce.stay_id,
    di.label,
    ce.charttime,
    ce.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  JOIN eligible_icu_stays eis ON ce.stay_id = eis.stay_id
  WHERE ce.charttime >= eis.intime
    AND ce.charttime <= DATETIME_ADD(eis.intime, INTERVAL 24 HOUR)
    AND di.label IN ('Heart Rate', 'Arterial Blood Pressure mean', 'Respiratory Rate', 'SpO2')
    AND ce.valuenum IS NOT NULL
),
vitals_flagged AS (
  -- Flag instability components
  SELECT
    stay_id,
    charttime,
    MAX(CASE WHEN label = 'Heart Rate' AND valuenum > 130 THEN 1 ELSE 0 END) AS tachycardia,
    MAX(CASE WHEN label = 'Arterial Blood Pressure mean' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension,
    MAX(CASE WHEN label = 'Respiratory Rate' AND valuenum > 30 THEN 1 ELSE 0 END) AS rr_high,
    MAX(CASE WHEN label = 'SpO2' AND valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low
  FROM vitals
  GROUP BY stay_id, charttime
),
instability_scores AS (
  -- Compute instability score per timestamp
  SELECT
    stay_id,
    charttime,
    hypotension,
    tachycardia,
    CASE
      WHEN hypotension = 1 OR tachycardia = 1 OR rr_high = 1 OR spo2_low = 1 THEN 1
      ELSE 0
    END AS unstable
  FROM vitals_flagged
),
instability_agg AS (
  -- Aggregate instability metrics per stay
  SELECT
    stay_id,
    AVG(CAST(hypotension AS FLOAT64)) AS hypotension_burden,
    AVG(CAST(tachycardia AS FLOAT64)) AS tachycardia_burden,
    AVG(CAST(unstable AS FLOAT64)) AS instability_score
  FROM instability_scores
  GROUP BY stay_id
),
final_data AS (
  -- Join all data
  SELECT
    sf.shock,
    ia.hypotension_burden,
    ia.tachycardia_burden,
    ia.instability_score,
    eis.los AS icu_los,
    CASE
      WHEN eis.outtime IS NOT NULL AND a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS icu_mortality
  FROM shock_flag sf
  JOIN eligible_icu_stays eis ON sf.stay_id = eis.stay_id
  JOIN instability_agg ia ON sf.stay_id = ia.stay_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON eis.hadm_id = a.hadm_id
)
-- Final aggregation
SELECT
  shock,
  COUNT(*) AS n_stays,
  AVG(hypotension_burden) AS mean_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(50)] AS median_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension_burden,
  AVG(tachycardia_burden) AS mean_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(50)] AS median_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia_burden,
  AVG(instability_score) AS mean_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median_instability_score,
  APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability_score,
  AVG(icu_los) AS mean_icu_los,
  AVG(CAST(icu_mortality AS FLOAT64)) AS mortality_rate
FROM final_data
GROUP BY shock
ORDER BY shock;