WITH heart_rate_item AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE label = 'Heart Rate'
),
icu_stays_with_age AS (
  SELECT 
    icu.subject_id, 
    icu.stay_id,
    p.gender,
    -- Calculate age at ICU admission: anchor_age + (ICU admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_icu
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
),
filtered_icu_stays AS (
  SELECT 
    subject_id,
    stay_id
  FROM icu_stays_with_age
  WHERE 
    gender = 'M' 
    AND age_at_icu BETWEEN 55 AND 65
),
heart_rate_events AS (
  SELECT 
    ce.subject_id,
    ce.valuenum AS heart_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_icu_stays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN heart_rate_item hri
    ON ce.itemid = hri.itemid
  WHERE ce.valuenum IS NOT NULL  -- Ensure numeric values
),
per_patient_max AS (
  SELECT 
    subject_id,
    MAX(heart_rate) AS max_hr
  FROM heart_rate_events
  GROUP BY subject_id
),
iqr_data AS (
  SELECT 
    APPROX_QUANTILES(max_hr, 4) AS quantiles  -- Returns [min, q1, median, q3, max]
  FROM per_patient_max
)
SELECT 
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr
FROM iqr_data;