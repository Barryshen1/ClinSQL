WITH 
-- Step 1: Patient selection and stroke type
stroke_patients AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    di.long_title AS diagnosis,
    CASE 
      WHEN di.icd_code LIKE 'I63%' THEN 'Ischemic'
      WHEN di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' THEN 'Hemorrhagic'
    END AS stroke_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 44 AND 54
    AND di.icd_version = 10  -- Assuming ICD-10 is used; adjust as necessary
),

-- Step 2: Calculate Elixhauser comorbidity score
elixhauser_score AS (
  WITH comorbidities AS (
    SELECT DISTINCT
      hadm_id,
      CASE
        WHEN icd_code IN ('E10.9', 'E11.9', 'E13.9', 'E14.9') THEN 1  -- Diabetes
        WHEN icd_code LIKE 'I25%' THEN 1  -- Coronary artery disease
        WHEN icd_code LIKE 'I50%' THEN 1  -- Heart failure
        -- Add more conditions as per Elixhauser comorbidity index definition
        ELSE 0
      END AS comorbidity
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      icd_version = 10
  ),
  score AS (
    SELECT 
      hadm_id,
      SUM(comorbidity) AS score
    FROM 
      comorbidities
    GROUP BY 
      hadm_id
  )
  SELECT 
    hadm_id,
    CASE 
      WHEN score IS NULL THEN 'Unknown'
      WHEN score <= 0 THEN 'Low'
      WHEN score BETWEEN 1 AND 4 THEN 'Med'
      ELSE 'High'
    END AS comorbidity_level
  FROM 
    score
),

-- Step 3: Calculate LOS, mortality, and stratify
patient_outcomes AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    sp.stroke_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN a.deathtime IS NOT NULL THEN 1 ELSE 0 END AS mortality,
    CASE WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5'
         ELSE '>5'
    END AS los_stratum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    stroke_patients sp ON a.hadm_id = sp.hadm_id
),

-- Step 4: Identify treatments (mechanical ventilation, vasopressors, RRT)
treatments AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Vent%') THEN 1 ELSE 0 END) AS mech_vent,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%Vasopressor%') THEN 1 ELSE 0 END) AS vasopressors,
    MAX(CASE WHEN itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%RRT%' OR label LIKE '%Dialysis%') THEN 1 ELSE 0 END) AS rrt
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents`
  GROUP BY 
    hadm_id
),

-- Step 5: Combine data and calculate required statistics
combined AS (
  SELECT 
    po.stroke_type,
    po.los_stratum,
    es.comorbidity_level,
    po.mortality,
    po.los,
    t.mech_vent,
    t.vasopressors,
    t.rrt
  FROM 
    patient_outcomes po
  LEFT JOIN 
    treatments t ON po.hadm_id = t.hadm_id
  LEFT JOIN 
    elixhauser_score es ON po.hadm_id = es.hadm_id
)

SELECT 
  stroke_type,
  los_stratum,
  comorbidity_level,
  COUNT(*) AS num_patients,
  AVG(mortality) * 100 AS mortality_percent,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  AVG(mech_vent) * 100 AS mech_vent_percent,
  AVG(vasopressors) * 100 AS vasopressors_percent,
  AVG(rrt) * 100 AS rrt_percent
FROM 
  combined
GROUP BY 
  stroke_type, los_stratum, comorbidity_level
ORDER BY 
  stroke_type, los_stratum, comorbidity_level;