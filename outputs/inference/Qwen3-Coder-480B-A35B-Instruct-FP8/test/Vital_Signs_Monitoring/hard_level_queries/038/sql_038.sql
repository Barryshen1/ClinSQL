WITH cohort_patients AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ie.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON ie.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
    AND LOWER(d_dx.long_title) LIKE '%status epilepticus%'
),

vitals_first72h AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN di.label = 'Arterial Systolic' THEN ce.valuenum ELSE NULL END) AS sys_bp,
    MAX(CASE WHEN di.label = 'Arterial Diastolic' THEN ce.valuenum ELSE NULL END) AS dias_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort_patients cp
    ON ce.stay_id = cp.stay_id
  WHERE
    ce.charttime >= cp.intime
    AND ce.charttime <= cp.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
    AND di.label IN ('Heart Rate', 'Arterial Systolic', 'Arterial Diastolic')
  GROUP BY ce.subject_id, ce.stay_id, ce.charttime
),

vii_scores AS (
  SELECT
    stay_id,
    charttime,
    CASE WHEN heart_rate > 120 OR heart_rate < 50 THEN 1 ELSE 0 END +
    CASE WHEN (sys_bp + 2 * dias_bp) / 3 < 65 THEN 1 ELSE 0 END AS vii_score
  FROM vitals_first72h
),

hourly_vii AS (
  SELECT
    stay_id,
    EXTRACT(HOUR FROM charttime) AS hour_of_stay,
    AVG(vii_score) AS avg_vii_per_hour
  FROM vii_scores
  GROUP BY stay_id, hour_of_stay
),

avg_vii_per_stay AS (
  SELECT
    stay_id,
    AVG(avg_vii_per_hour) AS mean_vii
  FROM hourly_vii
  GROUP BY stay_id
),

tachycardia_burden AS (
  SELECT
    stay_id,
    SUM(CASE WHEN heart_rate > 120 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS tachycardia_burden_pct
  FROM vitals_first72h
  GROUP BY stay_id
),

hypotension_burden AS (
  SELECT
    stay_id,
    SUM(CASE WHEN (sys_bp + 2 * dias_bp) / 3 < 65 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS map_lt65_burden_pct
  FROM vitals_first72h
  GROUP BY stay_id
),

cohort_metrics AS (
  SELECT
    'Status Epilepticus Female 63-73' AS cohort,
    AVG(mean_vii) AS mean_vii,
    APPROX_QUANTILES(mean_vii, 100)[OFFSET(25)] AS p25_vii,
    APPROX_QUANTILES(mean_vii, 100)[OFFSET(50)] AS p50_vii,
    APPROX_QUANTILES(mean_vii, 100)[OFFSET(75)] AS p75_vii,
    APPROX_QUANTILES(mean_vii, 100)[OFFSET(90)] AS p90_vii,
    AVG(tachycardia_burden_pct) AS avg_tachycardia_burden,
    AVG(map_lt65_burden_pct) AS avg_map_lt65_burden,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_patients cp
  LEFT JOIN avg_vii_per_stay vii ON cp.stay_id = vii.stay_id
  LEFT JOIN tachycardia_burden tb ON cp.stay_id = tb.stay_id
  LEFT JOIN hypotension_burden hb ON cp.stay_id = hb.stay_id
),

-- General ICU cohort
general_icu AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los AS icu_los,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
),

general_vitals AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN di.label = 'Arterial Systolic' THEN ce.valuenum ELSE NULL END) AS sys_bp,
    MAX(CASE WHEN di.label = 'Arterial Diastolic' THEN ce.valuenum ELSE NULL END) AS dias_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN general_icu gi
    ON ce.stay_id = gi.stay_id
  WHERE
    ce.charttime >= gi.intime
    AND ce.charttime <= gi.intime + INTERVAL 72 HOUR
    AND ce.valuenum IS NOT NULL
    AND di.label IN ('Heart Rate', 'Arterial Systolic', 'Arterial Diastolic')
  GROUP BY ce.subject_id, ce.stay_id, ce.charttime
),

general_vii_scores AS (
  SELECT
    stay_id,
    charttime,
    CASE WHEN heart_rate > 120 OR heart_rate < 50 THEN 1 ELSE 0 END +
    CASE WHEN (sys_bp + 2 * dias_bp) / 3 < 65 THEN 1 ELSE 0 END AS vii_score
  FROM general_vitals
),

general_hourly_vii AS (
  SELECT
    stay_id,
    EXTRACT(HOUR FROM charttime) AS hour_of_stay,
    AVG(vii_score) AS avg_vii_per_hour
  FROM general_vii_scores
  GROUP BY stay_id, hour_of_stay
),

general_avg_vii_per_stay AS (
  SELECT
    stay_id,
    AVG(avg_vii_per_hour) AS mean_vii
  FROM general_hourly_vii
  GROUP BY stay_id
),

general_tachycardia_burden AS (
  SELECT
    stay_id,
    SUM(CASE WHEN heart_rate > 120 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS tachycardia_burden_pct
  FROM general_vitals
  GROUP BY stay_id
),

general_hypotension_burden AS (
  SELECT
    stay_id,
    SUM(CASE WHEN (sys_bp + 2 * dias_bp) / 3 < 65 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS map_lt65_burden_pct
  FROM general_v;