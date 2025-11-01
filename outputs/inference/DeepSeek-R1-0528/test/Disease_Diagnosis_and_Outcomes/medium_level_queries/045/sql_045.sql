WITH pneumonia_icd AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND (
        icd_code LIKE '480%' OR 
        icd_code LIKE '481%' OR 
        icd_code LIKE '482%' OR 
        icd_code LIKE '483%' OR 
        icd_code LIKE '484%' OR 
        icd_code = '485' OR 
        icd_code = '486' OR 
        icd_code = '4870'  -- 487.0 without dot
    )) OR 
    (icd_version = 10 AND (
        icd_code LIKE 'J12%' OR 
        icd_code LIKE 'J13%' OR 
        icd_code LIKE 'J14%' OR 
        icd_code LIKE 'J15%' OR 
        icd_code LIKE 'J16%' OR 
        icd_code LIKE 'J18%'
    ))
),
aspiration_icd AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '507%') OR 
    (icd_version = 10 AND icd_code IN ('J69.0', 'J69.1', 'J69.8'))
),
cohort_base AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag AS mortality,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
    AND (
      (a.admission_type = 'EMERGENCY' AND a.hadm_id IN (SELECT hadm_id FROM pneumonia_icd))
      OR 
      a.hadm_id IN (SELECT hadm_id FROM aspiration_icd)
    )
),
cohort AS (
  SELECT 
    cb.*,
    -- Day-1 ICU flag (ICU admission within 24 hours)
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = cb.hadm_id
        AND i.intime <= DATETIME_ADD(cb.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS day1_icu,
    -- Mechanical ventilation flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = cb.hadm_id
        AND pe.itemid IN (227194, 225468, 225477)
    ) THEN 1 ELSE 0 END AS mech_vent,
    -- Vasopressor flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
      WHERE ie.hadm_id = cb.hadm_id
        AND ie.itemid IN (221906, 221289, 221750, 221662, 221653, 221749, 222315)
    ) THEN 1 ELSE 0 END AS vasopressor,
    -- RRT flag
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE pe.hadm_id = cb.hadm_id
        AND pe.itemid IN (225802, 225803, 225805, 225809, 225810, 225955)
    ) THEN 1 ELSE 0 END AS rrt
  FROM cohort_base cb
)
-- Results grouped by LOS category
SELECT 
  'los_group' AS category,
  CASE WHEN los_days <= 7 THEN '<=7' ELSE '>7' END AS group_name,
  COUNT(*) AS total_patients,
  SUM(mortality) AS mortality_count,
  ROUND(SUM(mortality) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  SUM(mech_vent) AS mech_vent_count,
  ROUND(SUM(mech_vent) * 100.0 / COUNT(*), 2) AS mech_vent_percentage,
  SUM(vasopressor) AS vasopressor_count,
  ROUND(SUM(vasopressor) * 100.0 / COUNT(*), 2) AS vasopressor_percentage,
  SUM(rrt) AS rrt_count,
  ROUND(SUM(rrt) * 100.0 / COUNT(*), 2) AS rrt_percentage
FROM cohort
GROUP BY group_name
UNION ALL
-- Results grouped by Day-1 ICU status
SELECT 
  'day1_icu' AS category,
  CASE WHEN day1_icu = 1 THEN 'Yes' ELSE 'No' END AS group_name,
  COUNT(*) AS total_patients,
  SUM(mortality) AS mortality_count,
  ROUND(SUM(mortality) * 100.0 / COUNT(*), 2) AS mortality_percentage,
  SUM(mech_vent) AS mech_vent_count,
  ROUND(SUM(mech_vent) * 100.0 / COUNT(*), 2) AS mech_vent_percentage,
  SUM(vasopressor) AS vasopressor_count,
  ROUND(SUM(vasopressor) * 100.0 / COUNT(*), 2) AS vasopressor_percentage,
  SUM(rrt) AS rrt_count,
  ROUND(SUM(rrt) * 100.0 / COUNT(*), 2) AS rrt_percentage
FROM cohort
GROUP BY group_name;