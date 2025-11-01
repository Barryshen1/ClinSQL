WITH PatientHeartFailure AS (
  -- Identify patients with heart failure diagnosis
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age >= 70 AND p.anchor_age <= 80
    AND d.icd_code LIKE 'I50%' -- Heart failure codes (I50.1, I50.2, I50.3, I50.4, I50.9)
), ICUStaysHeartFailure AS (
  -- Get ICU stays for patients with heart failure
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN PatientHeartFailure AS phf
    ON s.subject_id = phf.subject_id
), DiagnosticIntensity AS (
  -- Calculate diagnostic intensity for each ICU stay
  SELECT
    ishf.stay_id,
    COUNT(DISTINCT ce.itemid) AS diagnostic_intensity
  FROM ICUStaysHeartFailure AS ishf
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ishf.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN ishf.intime AND TIMESTAMP_ADD(ishf.intime, INTERVAL 72 HOUR)
  GROUP BY
    ishf.stay_id
), AllICUStays AS (
  -- Get all ICU stays
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
), DiagnosticIntensityAll AS (
  -- Calculate diagnostic intensity for all ICU stays
  SELECT
    ais.stay_id,
    COUNT(DISTINCT ce.itemid) AS diagnostic_intensity
  FROM AllICUStays AS ais
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ais.stay_id = ce.stay_id
  WHERE
    ce.charttime BETWEEN ais.intime AND TIMESTAMP_ADD(ais.intime, INTERVAL 72 HOUR)
  GROUP BY
    ais.stay_id
), HeartFailureSummary AS (
  -- Summarize diagnostic intensity for heart failure patients
  SELECT
    AVG(di.diagnostic_intensity) AS mean_diagnostic_intensity,
    MEDIAN(di.diagnostic_intensity) AS median_diagnostic_intensity,
    PERCENTILE_CONT(di.diagnostic_intensity, 0.75) AS p75_diagnostic_intensity,
    PERCENTILE_CONT(di.diagnostic_intensity, 0.95) AS p95_diagnostic_intensity,
    AVG(ishf.los) AS mean_icu_los,
    AVG(CASE WHEN ishf.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality -- Calculate hospital mortality
  FROM ICUStaysHeartFailure AS ishf
  JOIN DiagnosticIntensity AS di
    ON ishf.stay_id = di.stay_id
), AllICUSummary AS (
  -- Summarize diagnostic intensity for all ICU patients
  SELECT
    AVG(dia.diagnostic_intensity) AS mean_diagnostic_intensity,
    MEDIAN(dia.diagnostic_intensity) AS median_diagnostic_intensity,
    PERCENTILE_CONT(dia.diagnostic_intensity, 0.75) AS p75_diagnostic_intensity,
    PERCENTILE_CONT(dia.diagnostic_intensity, 0.95) AS p95_diagnostic_intensity,
    AVG(ais.los) AS mean_icu_los,
    AVG(CASE WHEN ais.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS hospital_mortality -- Calculate hospital mortality
  FROM AllIC;