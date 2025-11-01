WITH
-- Get male patients aged 57-67
patient_demo AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 57 AND 67
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    s.first_careunit,
    s.last_careunit,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    s.hadm_id = a.hadm_id
  WHERE
    s.subject_id IN (SELECT subject_id FROM patient_demo)
),

-- Identify transplant patients (using procedure codes)
transplant_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- Common transplant procedure codes (ICD-10-PCS)
    p.icd_code LIKE '0TY%'  -- Kidney transplant
    OR p.icd_code LIKE '0TY%' -- Heart transplant (example)
    -- Add other transplant codes as needed
),

-- Get vital signs for instability score calculation
vital_signs AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    di.label
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    ce.stay_id IN (SELECT stay_id FROM icu_stays)
    AND (
      -- Temperature (Fever >38.5°C)
      di.label LIKE '%Temp%' OR
      -- SpO2
      di.label LIKE '%SpO2%' OR
      -- Respiratory Rate
      di.label LIKE '%Respiratory Rate%'
    )
),

-- Calculate instability score components
instability_components AS (
  SELECT
    vs.subject_id,
    vs.hadm_id,
    vs.stay_id,
    MAX(CASE WHEN vs.label LIKE '%Temp%' AND vs.valuenum > 38.5 THEN 1 ELSE 0 END) AS fever_event,
    MAX(CASE WHEN vs.label LIKE '%SpO2%' AND vs.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_event,
    MAX(CASE WHEN vs.label LIKE '%Respiratory Rate%' AND vs.valuenum > 20 THEN 1 ELSE 0 END) AS rr_event
  FROM
    vital_signs vs
  JOIN
    icu_stays s
  ON
    vs.stay_id = s.stay_id
  WHERE
    -- Within first 72 hours of ICU stay
    TIMESTAMP_DIFF(vs.charttime, s.intime, HOUR) <= 72
  GROUP BY
    vs.subject_id, vs.hadm_id, vs.stay_id
),

-- Combine all metrics
patient_metrics AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.los AS icu_los,
    s.hospital_expire_flag,
    CASE WHEN tp.subject_id IS NOT NULL THEN 'Transplant' ELSE 'Non-Transplant' END AS transplant_status,
    (ic.fever_event + ic.spo2_event + ic.rr_event) AS instability_score
  FROM
    icu_stays s
  LEFT JOIN
    transplant_patients tp
  ON
    s.subject_id = tp.subject_id AND s.hadm_id = tp.hadm_id
  LEFT JOIN
    instability_components ic
  ON
    s.stay_id = ic.stay_id
)

-- Final comparison
SELECT
  transplant_status,
  COUNT(*) AS patient_count,
  -- Instability score metrics
  APPROX_QUANTILES(instability_score, 4)[OFFSET(1)] AS instability_score_median,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(0)] AS instability_score_25th,
  APPROX_QUANTILES(instability_score, 4)[OFFSET(2)] AS instability_score_75th,
  -- ICU LOS metrics
  APPROX_QUANTILES(icu_los, 4)[OFFSET(1)] AS icu_los_median,
  APPROX_QUANTILES(icu_los, 4)[OFFSET(0)] AS icu_los_25th,
  APPROX_QUANTILES(icu_los, 4)[OFFSET(2)] AS icu_los_75th,
  -- Mortality rate
  SUM(hospital_expire_flag) / COUNT(*) AS mortality_rate
FROM
  patient_metrics
GROUP BY
  transplant_status
ORDER BY
  transplant_status;