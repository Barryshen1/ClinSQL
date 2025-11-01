WITH
-- Get female patients aged 59-69
female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime AS icu_intime,
    s.outtime AS icu_outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  WHERE
    s.subject_id IN (SELECT subject_id FROM female_patients)
),

-- Identify patients with shock diagnosis
shock_patients AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
  ON
    d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.icd_code IN ('R57.0', 'R57.1', 'R57.9') -- Shock ICD codes
    AND d.subject_id IN (SELECT subject_id FROM female_patients)
),

-- Get MAP and heart rate measurements in first 24 hours
vital_signs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) AS hours_since_icu_admission,
    CASE
      WHEN c.itemid = 220050 THEN 'MAP'
      WHEN c.itemid = 220045 THEN 'Heart Rate'
    END AS measurement_type
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    icu_stays i
  ON
    c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.itemid IN (220050, 220045) -- MAP and Heart Rate
    AND TIMESTAMP_DIFF(c.charttime, i.icu_intime, HOUR) <= 24
),

-- Calculate hypotension and tachycardia burden
hypotension_tachycardia AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    SUM(CASE WHEN measurement_type = 'MAP' AND valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_count,
    SUM(CASE WHEN measurement_type = 'Heart Rate' AND valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_count,
    COUNT(CASE WHEN measurement_type = 'MAP' THEN 1 END) AS total_map_measurements,
    COUNT(CASE WHEN measurement_type = 'Heart Rate' THEN 1 END) AS total_hr_measurements
  FROM
    vital_signs
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Combine all data
combined_data AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.icu_los_hours,
    i.hospital_expire_flag,
    CASE WHEN s.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_shock,
    h.hypotension_count,
    h.tachycardia_count,
    h.total_map_measurements,
    h.total_hr_measurements,
    (h.hypotension_count / NULLIF(h.total_map_measurements, 0)) * 100 AS hypotension_burden,
    (h.tachycardia_count / NULLIF(h.total_hr_measurements, 0)) * 100 AS tachycardia_burden
  FROM
    icu_stays i
  LEFT JOIN
    shock_patients s
  ON
    i.subject_id = s.subject_id AND i.hadm_id = s.hadm_id
  LEFT JOIN
    hypotension_tachycardia h
  ON
    i.subject_id = h.subject_id AND i.hadm_id = h.hadm_id AND i.stay_id = h.stay_id
)

-- Final aggregation
SELECT
  has_shock,
  COUNT(*) AS patient_count,
  AVG(icu_los_hours) AS avg_icu_los_hours,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(25)] AS p25_icu_los,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(50)] AS p50_icu_los,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(75)] AS p75_icu_los,
  AVG(hypotension_burden) AS avg_hypotension_burden,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(25)] AS p25_hypotension,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(50)] AS p50_hypotension,
  APPROX_QUANTILES(hypotension_burden, 100)[OFFSET(75)] AS p75_hypotension,
  AVG(tachycardia_burden) AS avg_tachycardia_burden,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(25)] AS p25_tachycardia,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(50)] AS p50_tachycardia,
  APPROX_QUANTILES(tachycardia_burden, 100)[OFFSET(75)] AS p75_tachycardia,
  SUM(hospital_expire_flag) AS mortality_count,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS mortality_rate
FROM
  combined_data
GROUP BY
  has_shock
ORDER BY
  has_shock;