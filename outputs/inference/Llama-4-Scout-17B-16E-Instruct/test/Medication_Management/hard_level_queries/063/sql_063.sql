WITH 
-- Patient selection
patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code LIKE '481%'
    )
),

-- Medication prescriptions in first 24 hours
medications AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(DISTINCT drug) AS medication_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients)
    AND TIMESTAMP_ADD(admittime, INTERVAL 1 DAY) > starttime
  GROUP BY 
    subject_id, 
    hadm_id
),

-- ICU stays
icustays AS (
  SELECT 
    subject_id, 
    hadm_id, 
    stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients)
),

-- Calculate LOS and mortality
outcomes AS (
  SELECT 
    p.hadm_id, 
    DATE_DIFF(a.dischtime, a.admittime) AS los,
    IF(a.hospital_expire_flag = 1, 'Yes', 'No') AS mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    patients p
  ON 
    a.hadm_id = p.hadm_id
)

-- Final query
SELECT 
  -- Medication complexity distribution
  APPROX_QUANTILES(m.medication_count, 0.25)[OFFSET(0)] AS p25_medication_complexity,
  APPROX_QUANTILES(m.medication_count, 0.5)[OFFSET(0)] AS p50_medication_complexity,
  APPROX_QUANTILES(m.medication_count, 0.75)[OFFSET(0)] AS p75_medication_complexity,
  AVG(m.medication_count) AS mean_medication_complexity,

  -- LOS and mortality comparison
  AVG(CASE WHEN i.hadm_id IS NOT NULL THEN o.los END) AS los_icu,
  AVG(CASE WHEN i.hadm_id IS NULL THEN o.los END) AS los_non_icu,
  SUM(CASE WHEN i.hadm_id IS NOT NULL AND o.mortality = 'Yes' THEN 1 ELSE 0 END) / COUNT(CASE WHEN i.hadm_id IS NOT NULL THEN 1 END) AS mortality_icu,
  SUM(CASE WHEN i.hadm_id IS NULL AND o.mortality = 'Yes' THEN 1 ELSE 0 END) / COUNT(CASE WHEN i.hadm_id IS NULL THEN 1 END) AS mortality_non_icu
FROM 
  medications m
  JOIN 
  outcomes o
  ON 
  m.hadm_id = o.hadm_id
  LEFT JOIN 
  icustays i
  ON 
  o.hadm_id = i.hadm_id;