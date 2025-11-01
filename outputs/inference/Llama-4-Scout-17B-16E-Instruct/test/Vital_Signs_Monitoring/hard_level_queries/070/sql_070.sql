WITH 
-- Define vital signs itemids
vital_signs AS (
  SELECT 
    itemid,
    label
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE 
    label IN ('Heart Rate', 'Mean Arterial Pressure', 'Respiratory Rate')
),

-- Extract vital signs
vital_data AS (
  SELECT 
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    ce.charttime,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    vital_signs vs ON ce.itemid = vs.itemid
  WHERE 
    ce.valuenum IS NOT NULL
),

-- Calculate CV for each vital sign per patient
patient_cv AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    itemid,
    STDDEV(valuenum) / AVG(valuenum) AS cv
  FROM 
    vital_data
  GROUP BY 
    subject_id,
    hadm_id,
    stay_id,
    itemid
),

-- Sum CVs and filter patients of interest
filtered_patients AS (
  SELECT 
    pd.subject_id,
    ic.stay_id,
    ic.hadm_id,
    pd.anchor_age,
    pd.gender,
    SUM(pc.cv) AS total_cv
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` pd
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON pd.subject_id = ic.subject_id
  JOIN 
    patient_cv pc ON ic.subject_id = pc.subject_id AND ic.stay_id = pc.stay_id
  WHERE 
    pd.gender = 'M' AND
    pd.anchor_age BETWEEN 78 AND 88
  GROUP BY 
    pd.subject_id,
    ic.stay_id,
    ic.hadm_id,
    pd.anchor_age,
    pd.gender
),

-- Calculate quartiles
quartile_calc AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY total_cv DESC) AS quartile
  FROM 
    filtered_patients
),

top_quartile_patients AS (
  SELECT 
    subject_id,
    stay_id,
    hadm_id,
    anchor_age,
    gender,
    total_cv
  FROM 
    quartile_calc
  WHERE 
    quartile = 4
),

-- Calculate outcomes
outcomes AS (
  SELECT 
    tq.subject_id,
    tq.hadm_id,
    tq.stay_id,
    ic.los AS icu_los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 1 
      ELSE 0 
    END AS in_hospital_mortality
  FROM 
    top_quartile_patients tq
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON tq.stay_id = ic.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON tq.hadm_id = a.hadm_id
)

-- Final selection
SELECT 
  o.subject_id,
  o.hadm_id,
  o.stay_id,
  o.icu_los,
  o.in_hospital_mortality,
  -- We assume a simple instability score based on ICU LOS
  o.icu_los * o.in_hospital_mortality AS instability_score,
  -- Assign a decile based on total_cv
  PERCENT_RANK() OVER (ORDER BY o.total_cv) * 10 AS decile,
  -- Assume abnormal vital count is the number of vital signs with CV > 1
  SUM(CASE WHEN pc.cv > 1 THEN 1 ELSE 0 END) OVER (PARTITION BY o.subject_id, o.stay_id) AS abnormal_vital_count
FROM 
  outcomes o
JOIN 
  patient_cv pc ON o.subject_id = pc.subject_id AND o.stay_id = pc.stay_id
GROUP BY 
  o.subject_id,
  o.hadm_id,
  o.stay_id,
  o.icu_los,
  o.in_hospital_mortality,
  o.total_cv;