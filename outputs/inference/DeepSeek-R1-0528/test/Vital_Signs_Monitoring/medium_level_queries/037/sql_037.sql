WITH eligible_icu_stays AS (
  SELECT 
      icu.stay_id,
      icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE 
      pat.gender = 'F'
      AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) BETWEEN 88 AND 98
),
hfnc_stays AS (
  SELECT DISTINCT
      e.stay_id
  FROM eligible_icu_stays e
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON e.stay_id = ce.stay_id
  WHERE 
      ce.itemid = 226732  -- Oxygen Delivery Device
      AND (LOWER(ce.value) LIKE '%high flow nasal cannula%' 
           OR LOWER(ce.value) LIKE '%hfnc%')
),
gcs_events AS (
  SELECT 
      ce.valuenum AS gcs_total
  FROM hfnc_stays h
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON h.stay_id = ce.stay_id
  INNER JOIN eligible_icu_stays e
      ON h.stay_id = e.stay_id
  WHERE 
      ce.itemid IN (198, 226755)  -- GCS total itemids
      AND ce.valuenum IS NOT NULL  -- Ensure numeric value
      AND ce.charttime >= DATETIME_ADD(e.intime, INTERVAL 24 HOUR)  -- ICU day 2+
)
SELECT 
    APPROX_QUANTILES(gcs_total, 2)[OFFSET(1)] AS median_gcs_total
FROM gcs_events;