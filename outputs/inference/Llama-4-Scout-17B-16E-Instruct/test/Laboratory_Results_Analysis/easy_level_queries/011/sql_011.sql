WITH 
-- Identify potassium itemid
potassium_itemid AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label LIKE '%Potassium%'
),

-- Get peak potassium levels per ICU stay
peak_potassium AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS peak_potassium
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    potassium_itemid pi ON ce.itemid = pi.itemid
  WHERE 
    ce.valuenum IS NOT NULL 
    AND ce.valueuom = 'mEq/L'
  GROUP BY 
    ce.stay_id
)

-- Calculate standard deviation of peak potassium levels for 56-year-old males
SELECT 
  STDDEV(peak_potassium) AS stddev_peak_potassium
FROM 
  (
  SELECT 
    p.peak_potassium
  FROM 
    peak_potassium p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.stay_id = icu.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
  WHERE 
    pat.anchor_age = 56
    AND pat.gender = 'M'
  );