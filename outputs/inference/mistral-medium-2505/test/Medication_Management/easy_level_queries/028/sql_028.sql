WITH
-- Define common antiplatelet medications
antiplatelet_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) IN (
    'aspirin', 'clopidogrel', 'prasugrel', 'ticagrelor',
    'aspirin/extended release dipyridamole', 'dipyridamole',
    'cilostazol', 'ticlopidine'
  )
),

-- Get all antiplatelet prescriptions with patient and admission info
antiplatelet_rx AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    p.dose_val_rx,
    p.dose_unit_rx,
    p.route,
    a.admittime,
    a.dischtime,
    pat.gender,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  JOIN antiplatelet_drugs ad
    ON LOWER(p.drug) = LOWER(ad.drug)
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 44 AND 54
),

-- Identify patients on DAPT (2+ distinct antiplatelets in same admission)
dapt_patients AS (
  SELECT
    subject_id,
    hadm_id
  FROM antiplatelet_rx
  GROUP BY subject_id, hadm_id
  HAVING COUNT(DISTINCT drug) >= 2
),

-- Get single antiplatelet prescriptions (not part of DAPT)
single_antiplatelet_rx AS (
  SELECT
    ar.subject_id,
    ar.hadm_id,
    ar.drug,
    ar.starttime,
    ar.stoptime,
    ar.admittime,
    ar.dischtime,
    -- Calculate duration in hours (with type conversion)
    TIMESTAMP_DIFF(
      COALESCE(
        TIMESTAMP(ar.stoptime),
        TIMESTAMP(ar.dischtime),
        CURRENT_TIMESTAMP
      ),
      TIMESTAMP(ar.starttime),
      HOUR
    ) AS duration_hours
  FROM antiplatelet_rx ar
  LEFT JOIN dapt_patients dp
    ON ar.subject_id = dp.subject_id AND ar.hadm_id = dp.hadm_id
  WHERE dp.subject_id IS NULL  -- Not in DAPT group
    AND ar.starttime IS NOT NULL
    AND (ar.stoptime IS NOT NULL OR ar.dischtime IS NOT NULL)
)

-- Calculate standard deviation of single antiplatelet prescription durations
SELECT
  'Single Antiplatelet Prescription Duration' AS metric,
  COUNT(*) AS prescription_count,
  AVG(duration_hours) AS mean_duration_hours,
  STDDEV(duration_hours) AS stddev_duration_hours,
  MIN(duration_hours) AS min_duration_hours,
  MAX(duration_hours) AS max_duration_hours
FROM single_antiplatelet_rx
WHERE duration_hours > 0  -- Exclude zero or negative durations;