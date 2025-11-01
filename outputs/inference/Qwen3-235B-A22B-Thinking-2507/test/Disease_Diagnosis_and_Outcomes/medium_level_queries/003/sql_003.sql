WITH stroke_cohort AS (
  -- Identify male patients aged 44-54 with stroke
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    CASE 
      WHEN d.icd_version = 9 AND d.icd_code IN ('430', '431', '432') THEN 'hemorrhagic'
      WHEN d.icd_version = 10 AND d.icd_code IN ('I60', 'I61', 'I62') THEN 'hemorrhagic'
      WHEN d.icd_version = 9 AND d.icd_code IN ('433', '434') THEN 'ischemic'
      WHEN d.icd_version = 10 AND d.icd_code LIKE 'I63%' THEN 'ischemic'
      ELSE NULL
    END AS stroke_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432', '433', '434'))
      OR (d.icd_version = 10 AND (d.icd_code IN ('I60', 'I61', 'I62') OR d.icd_code LIKE 'I63%'))
    )
),

-- Filter to keep only one stroke type per admission (hemorrhagic takes precedence)
filtered_stroke AS (
  SELECT 
    subject_id,
    hadm_id,
    stroke_type
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY 
        CASE WHEN stroke_type = 'hemorrhagic' THEN 1 ELSE 2 END) AS priority
    FROM stroke_cohort
    WHERE stroke_type IS NOT NULL
  ) 
  WHERE priority = 1
),

-- Calculate hospital LOS and mortality
admission_details AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    f.stroke_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag AS died_in_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN filtered_stroke f ON a.hadm_id = f.hadm_id
),

-- Calculate comorbidity burden (count of non-stroke diagnoses)
comorbidity AS (
  SELECT 
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN filtered_stroke f ON d.hadm_id = f.hadm_id
  WHERE f.hadm_id IS NOT NULL  -- Only include patients in our stroke cohort
    AND NOT (
      (d.icd_version = 9 AND d.icd_code IN ('430', '431', '432', '433', '434'))
      OR (d.icd_version = 10 AND (d.icd_code IN ('I60', 'I61', 'I62') OR d.icd_code LIKE 'I63%'))
    )
  GROUP BY d.hadm_id
),

-- Determine comorbidity category
comorbidity_category AS (
  SELECT 
    hadm_id,
    comorbidity_count,
    CASE 
      WHEN comorbidity_count = 0 THEN 'low'
      WHEN comorbidity_count BETWEEN 1 AND 2 THEN 'medium'
      ELSE 'high'
    END AS comorbidity_level
  FROM comorbidity
),

-- Identify ICU stays for these patients
icu_stays AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN filtered_stroke f ON i.hadm_id = f.hadm_id
),

-- Identify patients who received mechanical ventilation
mech_vent AS (
  SELECT DISTINCT 
    i.hadm_id
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p 
    ON i.stay_id = p.stay_id
  WHERE p.itemid IN (225468, 225441, 225442, 225443, 225444, 225445, 225446, 225447, 225448, 225449, 225450)
),

-- Identify patients who received vasopressors
vasopressors AS (
  SELECT DISTINCT 
    i.hadm_id
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` inp 
    ON i.stay_id = inp.stay_id
  WHERE inp.itemid IN (221289, 221906, 222315, 221311, 222166, 221250, 221289)
),

-- Identify patients who received RRT
rrt AS (
  SELECT DISTINCT 
    i.hadm_id
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p 
    ON i.stay_id = p.stay_id
  WHERE p.itemid IN (225802, 225803, 225809, 225805, 225810, 227536, 227525)
),

-- Combine all information
final_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.stroke_type,
    a.los_days,
    a.died_in_hospital,
    c.comorbidity_level,
    -- Flag for mech vent, vasopressors, RRT
    CASE WHEN mv.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mech_vent_flag,
    CASE WHEN v.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS vasopressors_flag,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS rrt_flag
  FROM admission_details a
  LEFT JOIN comorbidity_category c ON a.hadm_id = c.hadm_id
  LEFT JOIN mech_vent mv ON a.hadm_id = mv.hadm_id
  LEFT JOIN vasopressors v ON a.hadm_id = v.hadm_id
  LEFT JOIN rrt r ON a.hadm_id = r.hadm_id
)

-- Final aggregation
SELECT
  stroke_type,
  CASE WHEN los_days <= 5 THEN '≤5' ELSE '>5' END AS los_group,
  comorbidity_level,
  COUNT(*) AS patient_count,
  AVG(died_in_hospital) * 100 AS mortality_rate,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  AVG(mech_vent_flag) * 100 AS pct_mech_vent,
  AVG(vasopressors_flag) * 100 AS pct_vasopressors,
  AVG(rrt_flag) * 100 AS pct_rrt
FROM final_data
GROUP BY stroke_type, los_group, comorbidity_level
ORDER BY stroke_type, los_group, comorbidity_level;