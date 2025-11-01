WITH PatientICU AS (
  -- Select relevant patient and ICU stay information
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ic.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 74 AND 84
),
InstabilityEvents AS (
  -- Identify instability events (fever, hypoxemia, tachypnea) within the first 48 hours of ICU stay
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ce.charttime,
    CASE
      WHEN ce.itemid = 220180 THEN 1 -- Fever > 38.5°C
      WHEN ce.itemid = 220181 THEN 1 -- SpO2 < 90%
      WHEN ce.itemid = 220182 THEN 1 -- RR > 20
      ELSE 0
    END AS instability_flag
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN PatientICU AS ic
    ON ce.subject_id = ic.subject_id AND ce.hadm_id = ic.hadm_id AND ce.stay_id = ic.stay_id
  WHERE
    ce.itemid IN (220180, 220181, 220182) -- Specific itemids for fever, SpO2, RR
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),
InstabilityHours AS (
  -- Calculate the total hours of instability for each patient
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNT(charttime) AS instability_hours
  FROM InstabilityEvents
  WHERE
    instability_flag = 1
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
),
InstabilitySummary AS (
  -- Calculate the 90th percentile of instability hours
  SELECT
    PERCENTILE_CONT(instability_hours, 0.90) AS p90_instability_hours
  FROM InstabilityHours
),
TopDecilePatients AS (
  -- Identify patients in the top decile of instability hours
  SELECT
    ih.subject_id,
    ih.hadm_id,
    ih.stay_id,
    ih.instability_hours
  FROM InstabilityHours AS ih
  JOIN InstabilitySummary AS isum
    ON ih.instability_hours >= isum.p90_instability_hours
),
TopDecileStats AS (
  -- Calculate statistics for the top decile patients
  SELECT
    COUNT(DISTINCT tdp.subject_id) AS n,
    AVG(ic.los) AS mean_icu_los,
    AVG(CASE WHEN ic.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_percent,
    AVG(ih.instability_hours) AS mean_instability_hours,
    AVG(
      SELECT
        COUNT(ce.charttime)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      WHERE
        ce.subject_id = tdp.subject_id
        AND ce.hadm_id = tdp.hadm_id
        AND ce.stay_id = tdp.stay_id
        AND ce.itemid = 220180 -- Fever > 38.5°C
        AND ce.charttime BETWEEN;