WITH 
-- Get the itemid for respiratory rate
respiratory_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Respiratory Rate%' AND (label LIKE '%(Total)%' OR label LIKE '%Total%')
),

-- Get patients within the specified age range and gender
target_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 51 AND 61
),

-- Get the first respiratory rate measurement for each ICU stay
first_respiratory_rate AS (
  SELECT 
    ce.subject_id,
    ce.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.hadm_id = icu.hadm_id AND ce.stay_id = icu.stay_id
  INNER JOIN target_patients tp ON ce.subject_id = tp.subject_id
  WHERE ce.itemid IN (SELECT itemid FROM respiratory_rate_itemid)
  AND ce.charttime >= icu.intime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) = 1
)

-- Calculate the 25th percentile of the first respiratory rates
SELECT 
  APPROX_QUANTILES(respiratory_rate, 100)[OFFSET(25)] AS percentile_25
FROM first_respiratory_rate;