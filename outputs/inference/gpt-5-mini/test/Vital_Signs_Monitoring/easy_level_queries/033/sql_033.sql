WITH hr_measurements AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
    ON ce.subject_id = s.subject_id
    AND ce.hadm_id = s.hadm_id
    AND ce.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    LOWER(di.label) LIKE '%heart rate%'           -- identify heart rate item(s)
    AND p.gender = 'F'                            -- female patients
    AND p.anchor_age BETWEEN 45 AND 55            -- age 45-55 inclusive
    AND ce.valuenum IS NOT NULL                   -- numeric values only
    AND ce.charttime >= s.intime
    AND ce.charttime <= s.outtime
    AND (TIMESTAMP_DIFF(ce.charttime, s.intime, DAY) + 1) >= 2  -- ICU day 2 or later
)

SELECT
  q[SAFE_OFFSET(1)] AS q1_heart_rate,
  q[SAFE_OFFSET(3)] AS q3_heart_rate,
  q[SAFE_OFFSET(3)] - q[SAFE_OFFSET(1)] AS iqr_heart_rate,
  q[SAFE_OFFSET(2)] AS median_heart_rate,
  q[SAFE_OFFSET(0)] AS min_heart_rate,
  q[SAFE_OFFSET(4)] AS max_heart_rate
FROM (
  SELECT APPROX_QUANTILES(valuenum, 4) AS q
  FROM hr_measurements
)
;