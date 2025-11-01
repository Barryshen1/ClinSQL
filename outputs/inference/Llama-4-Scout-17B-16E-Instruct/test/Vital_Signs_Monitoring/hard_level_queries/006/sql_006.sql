WITH 
-- Identify UGIB patients
ugib_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('K92.0', 'K22.0', 'K31.0')  -- UGIB related ICD codes
    )
),

-- Calculate vital instability index
vital_instability AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.charttime,
    CASE
      WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1  -- Tachycardia > 100
      WHEN ce.itemid = 220179 AND ce.valuenum < 65 THEN 1  -- MAP < 65
      WHEN ce.itemid = 220052 AND ce.valuenum > 20 THEN 1  -- Tachypnea > 20
      ELSE 0
    END AS instability_score
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE 
    ce.itemid IN (220050, 220179, 220052)  -- Heart Rate, Mean Arterial Pressure, Respiratory Rate
),

-- Aggregate instability scores
instability_agg AS (
  SELECT 
    subject_id, 
    hadm_id,
    SUM(instability_score) / COUNT(charttime) AS avg_instability_score
  FROM 
    vital_instability
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Calculate 95th percentile
percentile_95 AS (
  SELECT 
    APPROX_QUANTILES(avg_instability_score, 100)[OFFSET(95)] AS percentile_95_score
  FROM 
    instability_agg
),

-- Identify top decile patients
top_decile_patients AS (
  SELECT 
    subject_id, 
    hadm_id,
    avg_instability_score
  FROM 
    instability_agg
  WHERE 
    avg_instability_score > (SELECT percentile_95_score FROM percentile_95)
),

-- Age-matched controls
controls AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.hadm_id NOT IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('K92.0', 'K22.0', 'K31.0')
    )
)

-- Final comparison
SELECT 
  'Top Decile UGIB Patients' AS group_name,
  COUNT(DISTINCT tdp.hadm_id) AS num_patients,
  AVG(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia,
  AVG(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65,
  AVG(CASE WHEN ce.itemid = 220052 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea,
  AVG(i.los) AS icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(tdp.hadm_id) AS mortality
FROM 
  top_decile_patients tdp
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON tdp.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON tdp.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON tdp.subject_id = ce.subject_id AND tdp.hadm_id = ce.hadm_id

UNION ALL

SELECT 
  'Age-matched Controls' AS group_name,
  COUNT(DISTINCT c.hadm_id) AS num_patients,
  AVG(CASE WHEN ce.itemid = 220050 AND ce.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia,
  AVG(CASE WHEN ce.itemid = 220179 AND ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_lt_65,
  AVG(CASE WHEN ce.itemid = 220052 AND ce.valuenum > 20 THEN 1 ELSE 0 END) AS tachypnea,
  AVG(i.los) AS icu_los,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(c.hadm_id) AS mortality
FROM 
  controls c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.subject_id = ce.subject_id AND c.hadm_id = ce.hadm_id;