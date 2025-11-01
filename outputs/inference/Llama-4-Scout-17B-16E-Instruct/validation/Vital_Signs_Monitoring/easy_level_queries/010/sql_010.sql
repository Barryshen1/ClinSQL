WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
),
icustay_info AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu`.icustays i
),
dbp_info AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.valuenum AS dbp
  FROM 
    `physionet-data.mimiciv_3_1_icu`.chartevents c
  JOIN 
    `physionet-data.mimiciv_3_1_icu`.d_items d ON c.itemid = d.itemid
  WHERE 
    d.label = 'Diastolic blood pressure'
    AND c.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(dbp, 1000)[500] AS median_dbp
FROM (
  SELECT 
    i.stay_id,
    MAX(d.dbp) AS dbp
  FROM 
    patient_info p
  JOIN 
    icustay_info i ON p.subject_id = i.subject_id
  JOIN 
    dbp_info d ON i.stay_id = d.stay_id
  GROUP BY 
    i.stay_id
);