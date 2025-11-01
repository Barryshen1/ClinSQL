WITH
-- Get the itemid for MAP (Mean Arterial Pressure)
map_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Mean Arterial Pressure'
),

-- Filter patients: males aged 48-58
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 48 AND 58
),

-- Get ICU stays for these patients
icu_stays AS (
  SELECT s.subject_id, s.hadm_id, s.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN filtered_patients p ON s.subject_id = p.subject_id
),

-- Get MAP measurements for these stays
map_measurements AS (
  SELECT
    c.stay_id,
    c.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN icu_stays s ON c.subject_id = s.subject_id AND c.hadm_id = s.hadm_id AND c.stay_id = s.stay_id
  JOIN map_itemid m ON c.itemid = m.itemid
  WHERE c.valuenum IS NOT NULL
),

-- Calculate max MAP for each stay
max_map_per_stay AS (
  SELECT
    stay_id,
    MAX(map_value) AS max_map
  FROM map_measurements
  GROUP BY stay_id
)

-- Calculate the average of these max MAP values
SELECT
  AVG(max_map) AS avg_max_map_across_stays
FROM max_map_per_stay;