WITH PatientCohort AS (
  -- Select patients matching the criteria: female, age 56-66, diagnosed with ICH
  SELECT DISTINCT
    p.subject_id,
    p.gender,
    p.anchor_age,
    di.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND di.icd_code = 'I61' -- ICD-9 code for Intracranial Hemorrhage
), ICUStays AS (
  -- Select ICU stays for the cohort patients
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN PatientCohort AS pc
    ON s.subject_id = pc.subject_id
), DiagnosticEvents AS (
  -- Select diagnostic events (lab events, microbiology events, procedure events) within the first 72 hours of ICU stay
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.charttime,
    le.itemid,
    le.value,
    le.valuenum,
    le.valueuom,
    me.test_name,
    pe.itemid AS procedure_itemid,
    pe.value AS procedure_value,
    pe.valueuom AS procedure_valueuom
  FROM ICUStays AS s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.labevents` AS le
    ON s.subject_id = le.subject_id AND s.stay_id = le.stay_id AND le.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.microbiologyevents` AS me
    ON s.subject_id = me.subject_id AND s.stay_id = me.stay_id AND me.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
    ON s.subject_id = pe.subject_id AND s.stay_id = pe.stay_id AND pe.starttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
), DiagnosticIntensity AS (
  -- Calculate the number of diagnostic events per patient within the first 72 hours
  SELECT
    subject_id,
    stay_id,
    COUNT(*) AS diagnostic_event_count
  FROM DiagnosticEvents
  GROUP BY
    subject_id,
    stay_id
)
-- Calculate the 95th percentile of diagnostic intensity for the cohort
SELECT
  PERCENTILE_CONT(0.95, diagnostic_event_count) AS percentile_95_diagnostic_intensity
FROM DiagnosticIntensity;