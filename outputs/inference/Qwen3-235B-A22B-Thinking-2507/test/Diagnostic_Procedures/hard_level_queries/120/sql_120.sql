WITH 
-- Identify patients meeting demographic criteria and with upper GI bleeding diagnosis
admissions_cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 74 AND 84
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code IN (
          'K250', 'K252', 'K253', 'K255', 'K256',  -- Gastric ulcer hemorrhage
          'K260', 'K262', 'K263', 'K265', 'K266',  -- Duodenal ulcer hemorrhage
          'K270', 'K272', 'K273', 'K275', 'K276',  -- Peptic ulcer hemorrhage
          'K280', 'K282', 'K283', 'K285', 'K286',  -- Gastrojejunal ulcer hemorrhage
          'K920', 'K921', 'K922'                   -- Hematemesis/melena
        )
    )
),

-- Get first ICU stay for each qualifying admission
first_icu_stay AS (
  SELECT 
    i.hadm_id,
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN admissions_cohort a
    ON i.hadm_id = a.hadm_id
),
first_stay AS (
  SELECT *
  FROM first_icu_stay
  WHERE rn = 1
),

-- Calculate diagnostic intensity (labs + micro in first 72h)
diagnostic_intensity AS (
  SELECT 
    s.stay_id,
    s.hadm_id,
    s.subject_id,
    s.intime,
    -- Count lab events in first 72h
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
      WHERE l.subject_id = s.subject_id
        AND l.hadm_id = s.hadm_id
        AND l.charttime >= s.intime
        AND l.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    ), 0) AS lab_count,
    -- Count microbiology events in first 72h
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
      WHERE m.subject_id = s.subject_id
        AND m.hadm_id = s.hadm_id
        AND m.charttime >= s.intime
        AND m.charttime < TIMESTAMP_ADD(s.intime, INTERVAL 72 HOUR)
    ), 0) AS micro_count
  FROM first_stay s
),

-- Add procedure count, hospital LOS, and mortality
patient_metrics AS (
  SELECT 
    di.stay_id,
    di.hadm_id,
    di.subject_id,
    di.lab_count + di.micro_count AS diagnostic_intensity,
    -- Procedure count for the admission
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
      WHERE p.hadm_id = di.hadm_id
    ), 0) AS procedure_count,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS hospital_los,
    a.hospital_expire_flag
  FROM diagnostic_intensity di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON di.hadm_id = a.hadm_id
),

-- Assign quartiles based on diagnostic intensity
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY diagnostic_intensity) AS intensity_quartile
  FROM patient_metrics
)

-- Aggregate results by quartile
SELECT 
  intensity_quartile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los) AS mean_hospital_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM quartiles
GROUP BY intensity_quartile
ORDER BY intensity_quartile;