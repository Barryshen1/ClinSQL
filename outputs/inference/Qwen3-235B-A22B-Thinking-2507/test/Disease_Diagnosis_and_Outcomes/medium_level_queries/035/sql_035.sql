WITH patients_of_interest AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 69 AND 79
),

gi_bleed_diagnoses AS (
  SELECT
    d.hadm_id,
    d.icd_code,
    d.seq_num,
    CASE
      WHEN d.icd_code LIKE 'I85.0%' OR
           d.icd_code LIKE 'K25.%' OR
           d.icd_code LIKE 'K26.%' OR
           d.icd_code LIKE 'K27.%' OR
           d.icd_code LIKE 'K28.%'
        THEN 'upper'
      WHEN d.icd_code LIKE 'K55.2%' OR
           d.icd_code LIKE 'K57.%' OR
           d.icd_code = 'K62.5' OR
           d.icd_code = 'K63.5' OR
           d.icd_code LIKE 'K64%' OR
           d.icd_code LIKE 'I84%'
        THEN 'lower'
      ELSE NULL
    END AS bleed_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_version = 10
    AND (
      d.icd_code LIKE 'I85.0%' OR
      d.icd_code LIKE 'K25.%' OR
      d.icd_code LIKE 'K26.%' OR
      d.icd_code LIKE 'K27.%' OR
      d.icd_code LIKE 'K28.%' OR
      d.icd_code LIKE 'K55.2%' OR
      d.icd_code LIKE 'K57.%' OR
      d.icd_code = 'K62.5' OR
      d.icd_code = 'K63.5' OR
      d.icd_code LIKE 'K64%' OR
      d.icd_code LIKE 'I84%'
    )
),

primary_bleed_type AS (
  SELECT
    hadm_id,
    bleed_type
  FROM (
    SELECT
      hadm_id,
      bleed_type,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS rn
    FROM gi_bleed_diagnoses
    WHERE bleed_type IS NOT NULL
  )
  WHERE rn = 1
),

admission_metrics AS (
  SELECT
    poi.hadm_id,
    poi.gender,
    poi.age_at_admission,
    poi.hospital_expire_flag,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(poi.dischtime, poi.admittime, DAY) AS los_days,
    -- Determine day-1 ICU status
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = poi.hadm_id
        AND i.intime < TIMESTAMP_ADD(poi.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS day1_icu,
    -- Determine any ICU admission during stay
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
      WHERE i.hadm_id = poi.hadm_id
    ) THEN 1 ELSE 0 END AS any_icu
  FROM patients_of_interest poi
  INNER JOIN primary_bleed_type pbt
    ON poi.hadm_id = pbt.hadm_id
  WHERE pbt.bleed_type IN ('upper', 'lower')
    AND TIMESTAMP_DIFF(poi.dischtime, poi.admittime, DAY) >= 1  -- Only include LOS >=1 day
)

SELECT
  pbt.bleed_type,
  CASE
    WHEN am.los_days BETWEEN 1 AND 2 THEN '1-2'
    WHEN am.los_days BETWEEN 3 AND 5 THEN '3-5'
    WHEN am.los_days BETWEEN 6 AND 9 THEN '6-9'
    WHEN am.los_days >= 10 THEN '>=10'
  END AS los_group,
  CASE am.day1_icu
    WHEN 1 THEN 'ICU on day 1'
    ELSE 'No ICU on day 1'
  END AS day1_icu_status,
  COUNT(*) AS patient_count,
  ROUND(100.0 * SUM(am.hospital_expire_flag) / COUNT(*), 2) AS mortality_rate,
  ROUND(100.0 * SUM(am.any_icu) / COUNT(*), 2) AS icu_admission_rate
FROM admission_metrics am
INNER JOIN primary_bleed_type pbt
  ON am.hadm_id = pbt.hadm_id
GROUP BY 1, 2, 3
ORDER BY 
  pbt.bleed_type,
  CASE los_group
    WHEN '1-2' THEN 1
    WHEN '3-5' THEN 2
    WHEN '6-9' THEN 3
    WHEN '>=10' THEN 4
  END,
  day1_icu_status;