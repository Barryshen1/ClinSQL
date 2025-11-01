WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 62 AND 72
),
spo2_data AS (
  SELECT 
    cd.subject_id,
    cd.valuenum AS spo2_value,
    cd.charttime
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` cd
  JOIN 
    patient_data pd ON cd.subject_id = pd.subject_id
  WHERE 
    cd.itemid = 220050  -- SpO2
    AND cd.valuenum IS NOT NULL
),
first_spo2_data AS (
  SELECT 
    subject_id,
    spo2_value,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime) AS rn
  FROM 
    spo2_data
)
SELECT 
  QUANTILE(ARRAY_AGG(spo2_value ORDER BY spo2_value), 0.75) - 
  QUANTILE(ARRAY_AGG(spo2_value ORDER BY spo2_value), 0.25) AS iqr
FROM 
  first_spo2_data
WHERE 
  rn = 1;