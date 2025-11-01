WITH male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_with_icu AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.dischtime,
    DATE(a.dischtime) AS discharge_day
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN male_patients m ON a.subject_id = m.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON a.hadm_id = i.hadm_id
),
potassium_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%potassium%' 
    AND category = 'Electrolytes'
    AND fluid = 'Serum'
),
discharge_day_potassium AS (
  SELECT 
    l.valuenum AS potassium_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN admissions_with_icu a 
    ON l.subject_id = a.subject_id 
    AND l.hadm_id = a.hadm_id
    AND DATE(l.charttime) = a.discharge_day
    AND l.charttime <= a.dischtime  -- Ensure measurement before discharge
  INNER JOIN potassium_itemids p 
    ON l.itemid = p.itemid
  WHERE l.valuenum IS NOT NULL  -- Exclude missing values
)
SELECT 
  APPROX_QUANTILES(potassium_value, 100)[OFFSET(75)] AS potassium_75th_percentile
FROM discharge_day_potassium;