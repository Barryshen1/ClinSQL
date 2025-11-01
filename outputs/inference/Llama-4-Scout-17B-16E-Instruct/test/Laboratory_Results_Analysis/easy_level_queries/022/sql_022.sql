WITH 
-- Identify itemid for arterial blood gas pH
ph_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Arterial Blood Gas pH%'
),

-- Select relevant data
icu_data AS (
  SELECT 
    c.subject_id,
    c.valuenum AS pH
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` i 
      ON c.itemid = i.itemid
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON c.subject_id = p.subject_id
  WHERE 
    i.itemid = (SELECT itemid FROM ph_itemid)
    AND p.gender = 'M'
    AND c.valuenum IS NOT NULL
),

-- Calculate peak pH for each subject
peak_pH_data AS (
  SELECT 
    subject_id,
    MAX(pH) AS peak_pH
  FROM 
    icu_data
  GROUP BY 
    subject_id
)

-- Calculate IQR of peak pH
SELECT 
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(1)] AS Q1,
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(3)] AS Q3,
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(3)] - 
  APPROX_QUANTILES(peak_pH, 4)[OFFSET(1)] AS IQR
FROM 
  peak_pH_data;