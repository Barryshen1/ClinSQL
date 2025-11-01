WITH diastolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastol%'
),

dbp_events AS (
  -- diastolic measurements from chartevents only (datetimesevents not present in this dataset)
  SELECT subject_id, hadm_id, stay_id, charttime, valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE valuenum IS NOT NULL
    AND itemid IN (SELECT itemid FROM diastolic_items)
    AND valuenum BETWEEN 10 AND 200
),

eligible_stays AS (
  -- male patients age 49-59 and stays in units that look like step-down/IMC
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(icu.first_careunit) LIKE '%step%'
      OR LOWER(icu.first_careunit) LIKE '%stepdown%'
      OR LOWER(icu.first_careunit) LIKE '%pcu%'
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.first_careunit) LIKE '%progressive%'
    )
),

per_stay_mean AS (
  -- compute mean diastolic BP per eligible stay (only events within the stay)
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(e.valuenum) AS mean_dbp,
    COUNT(*) AS n_obs
  FROM eligible_stays s
  JOIN dbp_events e
    USING(stay_id, subject_id, hadm_id)
  WHERE e.charttime BETWEEN s.intime AND s.outtime
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
)

-- compute Q1, Q3 and IQR across per-stay means
SELECT
  arr[OFFSET(1)] AS q1_mean_dbp,
  arr[OFFSET(3)] AS q3_mean_dbp,
  SAFE_CAST(arr[OFFSET(3)] - arr[OFFSET(1)] AS FLOAT64) AS iqr_mean_dbp,
  (SELECT COUNT(*) FROM per_stay_mean) AS n_stays
FROM (
  SELECT APPROX_QUANTILES(mean_dbp, 4) AS arr
  FROM per_stay_mean
);