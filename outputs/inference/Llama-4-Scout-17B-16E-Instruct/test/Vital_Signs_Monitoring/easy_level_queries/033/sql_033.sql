WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT p.subject_id, p.gender, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 45 AND 55
  ),

  -- Join patients with ICU stays
  icu_stays AS (
    SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN patients_of_interest p ON i.subject_id = p.subject_id
  ),

  -- Filter heart rate events
  heart_rate_events AS (
    SELECT c.subject_id, c.stay_id, c.charttime, c.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    WHERE c.itemid = 220050  # Heart Rate
      AND c.valuenum IS NOT NULL
  ),

  -- Calculate ICU day for each heart rate event
  heart_rate_by_day AS (
    SELECT 
      h.subject_id,
      h.stay_id,
      DATE_DIFF(h.charttime, i.intime, DAY) AS icu_day,
      h.valuenum AS heart_rate
    FROM heart_rate_events h
    JOIN icu_stays i ON h.subject_id = i.subject_id AND h.stay_id = i.stay_id
    WHERE DATE_DIFF(h.charttime, i.intime, DAY) >= 2  # ICU day 2 and beyond
  )

-- Calculate IQR of heart rate
SELECT 
  APPROX_QUANTILES(heart_rate, 0.25)[OFFSET(0)] AS q1,
  APPROX_QUANTILES(heart_rate, 0.75)[OFFSET(0)] AS q3
FROM heart_rate_by_day;