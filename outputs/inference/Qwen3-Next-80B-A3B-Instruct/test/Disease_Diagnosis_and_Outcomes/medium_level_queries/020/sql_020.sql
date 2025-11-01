WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND (
      -- ICD-9 sepsis (exclude septic shock)
      (d.icd_version = 9 AND d.icd_code = '995.91')
      OR
      -- ICD-10 sepsis without shock (exclude septic shock)
      (d.icd_version = 10 AND d.icd_code IN ('A41.9', 'A41.5', 'A41.89', 'R65.20'))
    )
    AND NOT (
      -- Exclude septic shock
      (d.icd_version = 9 AND d.icd_code = '995.92')
      OR
      (d.icd_version = 10 AND d.icd_code IN ('A41.81', 'R65.21'))
    )
),

icu_day1 AS (
  SELECT DISTINCT
    i.hadm_id,
    CASE 
      WHEN i.intime >= s.admittime 
        AND i.intime <= TIMESTAMP_ADD(s.admittime, INTERVAL 24 HOUR) 
      THEN 1 
      ELSE 0 
    END AS icu_on_day1
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN sepsis_patients s
    ON i.hadm_id = s.hadm_id
),

los_categories AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.deathtime,
    s.hospital_expire_flag,
    s.anchor_age,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) AS los_days,
    -- Categorize LOS
    CASE
      WHEN TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) <= 3 THEN '<=3'
      WHEN TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) BETWEEN 4 AND 6 THEN '4-6'
      WHEN TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) BETWEEN 7 AND 10 THEN '7-10'
      WHEN TIMESTAMP_DIFF(s.dischtime, s.admittime, DAY) > 10 THEN '>10'
    END AS los_category,
    -- Days to death (only for those who died)
    CASE 
      WHEN s.hospital_expire_flag = 1 
      THEN TIMESTAMP_DIFF(s.deathtime, s.admittime, DAY)
    END AS days_to_death,
    COALESCE(i.icu_on_day1, 0) AS icu_on_day;