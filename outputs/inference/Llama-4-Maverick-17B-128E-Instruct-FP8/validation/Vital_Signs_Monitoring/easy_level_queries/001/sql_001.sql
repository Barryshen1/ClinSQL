WITH 
-- Filter male patients aged 52-62
relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
),

-- Get relevant ICU stays
relevant_icustays AS (
  SELECT icu.stay_id, icu.subject_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN relevant_patients p ON icu.subject_id = p.subject_id
),

-- Get the first MAP measurement for each ICU stay
first_map AS (
  SELECT ri.stay_id, ce.valuenum AS first_map_value
  FROM relevant_icustays ri
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ri.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label = 'Mean Arterial Pressure' AND ce.charttime >= ri.intime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ri.stay_id ORDER BY ce.charttime) = 1
)

-- Calculate the IQR of the first-recorded MAP
SELECT 
  APPROX_QUANTILES(first_map_value, 100)[
    OFFSET(25)] AS Q1,
  APPROX_QUANTILES(first_map_value, 100)[
    OFFSET(50)] AS median,
  APPROX_QUANTILES(first_map_value, 100)[
    OFFSET(75)] AS Q3,
  APPROX_QUANTILES(first_map_value, 100)[
    OFFSET(75)] - APPROX_QUANTILES(first_map_value, 100)[
    OFFSET(25)] AS IQR
FROM first_map;