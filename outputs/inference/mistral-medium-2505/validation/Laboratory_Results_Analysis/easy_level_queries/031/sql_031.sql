WITH
-- Get male patients with ICU stays
male_patients_with_icu AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
),

-- Get discharge day for these patients
discharge_days AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATE(a.dischtime) AS discharge_date
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients_with_icu m ON a.subject_id = m.subject_id
),

-- Get potassium itemid (assuming 'Potassium' is in the label)
potassium_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
  LIMIT 1  -- Assuming one itemid for potassium
),

-- Get potassium measurements on discharge day
potassium_on_discharge AS (
  SELECT
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN discharge_days d ON l.subject_id = d.subject_id AND l.hadm_id = d.hadm_id
  JOIN potassium_itemid k ON l.itemid = k.itemid
  WHERE DATE(l.charttime) = d.discharge_date
    AND l.valuenum IS NOT NULL
)

-- Calculate the 75th percentile
SELECT
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS potassium_75th_percentile
FROM potassium_on_discharge
LIMIT 1;