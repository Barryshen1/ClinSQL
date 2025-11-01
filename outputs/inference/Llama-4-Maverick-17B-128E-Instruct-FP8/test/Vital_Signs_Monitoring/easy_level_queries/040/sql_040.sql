WITH 
-- Filter male patients aged 55-65 and get their ICU stays
eligible_patients AS (
  SELECT p.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 55 AND 65
),

-- Get the itemid for Mean Arterial Pressure (MAP)
map_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Mean Arterial Pressure' OR abbreviation = 'MAP'
),

-- Get the first MAP measurement for each ICU stay
first_map AS (
  SELECT icu.stay_id, ce.valuenum, ROW_NUMBER() OVER (PARTITION BY icu.stay_id ORDER BY ce.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON icu.stay_id = ce.stay_id
  JOIN map_itemid ON ce.itemid = map_itemid.itemid
  WHERE ce.stay_id IN (SELECT stay_id FROM eligible_patients)
)

-- Calculate the standard deviation of the first MAP measurements
SELECT STDDEV(valuenum) AS sd_first_map
FROM first_map
WHERE rn = 1;