WITH hfnc_stays AS (
  -- First, identify all ICU stays where High Flow Nasal Cannula was used.
  -- This creates an explicit list of stays to filter on later.
  SELECT DISTINCT stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE
    itemid = 226732 -- O2 Delivery Device(s)
    AND value = 'High Flow Nasal Cannula'
),
gcs_events AS (
  -- Second, gather all relevant GCS Total scores for the specific patient cohort and time window.
  SELECT
    icu.stay_id,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
    AND ce.itemid = 226758 -- GCS Total
    AND ce.valuenum IS NOT NULL
    -- Filter for ICU day 2 or later.
    -- DATETIME_DIFF with DAY returns the number of full 24-hour periods that have passed.
    -- Day 1: diff = 0. Day 2: diff = 1. So we need diff >= 1.
    AND DATETIME_DIFF(ce.charttime, icu.intime, DAY) >= 1
)
-- Finally, join the GCS events with the HFNC stays and calculate the median.
-- The INNER JOIN ensures we only consider GCS scores from patients who were on HFNC.
SELECT
  APPROX_QUANTILES(gcs.valuenum, 2)[OFFSET(1)] AS median_gcs_total
FROM gcs_events AS gcs
INNER JOIN hfnc_stays AS hfnc
  ON gcs.stay_id = hfnc.stay_id;