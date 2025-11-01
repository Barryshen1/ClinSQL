WITH first_admission AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.dischtime IS NOT NULL
),
anticoagulant_prescriptions AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE 
    LOWER(drug) IN (
      'warfarin', 'heparin', 'enoxaparin', 'dalteparin', 'tinzaparin', 
      'dabigatran', 'rivaroxaban', 'apixaban', 'edoxaban', 'fondaparinux',
      'argatroban', 'bivalirudin', 'low molecular weight heparin', 'unfractionated heparin',
      'heparin sodium', 'heparin calcium', 'heparin lock flush', 'heparin flush'
    )
)
SELECT 
  STDDEV(EXTRACT(DAY FROM (fa.dischtime - fa.admittime))) AS sd_los_days
FROM 
  first_admission fa
INNER JOIN 
  anticoagulant_prescriptions ap
  ON fa.subject_id = ap.subject_id 
  AND fa.hadm_id = ap.hadm_id
WHERE 
  fa.rn = 1;