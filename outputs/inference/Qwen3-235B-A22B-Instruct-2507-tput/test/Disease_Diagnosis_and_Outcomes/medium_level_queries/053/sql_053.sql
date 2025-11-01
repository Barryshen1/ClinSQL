WITH elixhauser_conditions AS (
  SELECT 'I50' AS icd_code_prefix, 'heart_failure' AS condition
  UNION ALL SELECT 'E11', 'diabetes' 
  UNION ALL SELECT 'N18', 'renal_failure'
  UNION ALL SELECT 'I10', 'hypertension'
  UNION ALL SELECT 'I48', 'arrhythmia'
  UNION ALL SELECT 'J44', 'copd'
  UNION ALL SELECT 'C', 'cancer'
  UNION ALL SELECT 'K70', 'liver_disease'
  UNION ALL SELECT 'E66', 'obesity'
  UNION ALL SELECT 'F32', 'depression'
),
pneumonia_codes AS (
  SELECT 'J69.0' AS icd_code, 'aspiration' AS pneumonia_type
  UNION ALL
  SELECT 'J18.9', 'community'
  UNION ALL
  SELECT 'J13', 'community'
  UNION ALL
  SELECT 'J14', 'community'
  UNION ALL
  SELECT 'J15.9', 'community'
),
patients_with_pneumonia AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) AS age_at_admit,
    -- Determine pneumonia type
    CASE 
      WHEN di.icd_code = 'J69.0' THEN 'aspiration'
      ELSE 'community'
    END AS pneumonia_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN pneumonia_codes pc ON di.icd_code = pc.icd_code
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 39 AND 49
),
pneumonia_with_los_icu AS (
  SELECT
    pwp.*,
    -- Calculate LOS in days
    DATETIME_DIFF(pwp.dischtime, pwp.admittime, HOUR) / 24.0 AS los_days,
    -- ICU on day 1: ICU intime within 24h of admission and overlaps
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS icu_day1
  FROM patients_with_pneumonia pwp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pwp.hadm_id = i.hadm_id
    AND i.intime < DATETIME_ADD(pwp.admittime, INTERVAL 24 HOUR)
    AND i.outtime >= pwp.admittime
),
pneumonia_with_comorbidities AS (
  SELECT
    p.*,
    -- Count number of distinct elixhauser conditions per patient
    COALESCE(COUNT(DISTINCT ec.condition), 0) AS comorbidity_count
  FROM pneumonia_with_los_icu p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON p.hadm_id = di.hadm_id
  LEFT JOIN elixhauser_conditions ec 
    ON di.icd_code LIKE CONCAT(ec.icd_code_prefix, '%')
  GROUP BY p.subject_id, p.hadm_id, p.admittime, p.dischtime, p.hospital_expire_flag, 
           p.anchor_age, p.anchor_year, p.age_at_admit, p.pneumonia_type, 
           p.los_days, p.icu_day1
),
final_cohort AS (
  SELECT
    pneumonia_type,
    CASE
      WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
      WHEN los_days > 3 AND los_days <= 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '>=8 days'
      ELSE NULL
    END AS los_group,
    icu_day1,
    hospital_expire_flag,
    comorbidity_count
  FROM pneumonia_with_comorbidities
  WHERE los_days IS NOT NULL AND los_days > 0  -- Exclude negative/zero LOS
)
SELECT
  pneumonia_type,
  los_group,
  icu_day1,
  COUNT(*) AS n,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_rate_pct,
  AVG(comorbidity_count) AS avg_comorbidity_count
FROM final_cohort
WHERE los_group IS NOT NULL
GROUP BY pneumonia_type, los_group, icu_day1
ORDER BY pneumonia_type, los_group, icu_day1;