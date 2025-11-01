WITH bp_items AS (
  -- systolic BP items (invasive and non-invasive). Adjust the pattern if you want to narrow item selection.
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

eligible_stays AS (
  -- female ICU stays where recorded anchor_age is between 75 and 85
  SELECT ic.subject_id, ic.hadm_id, ic.stay_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

bp_first48 AS (
  -- per-stay mean systolic BP within the first 48 hours of ICU stay
  SELECT
    es.stay_id,
    AVG(ce.valuenum) AS mean_sbp,
    COUNT(*) AS n_meas
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = es.stay_id
  JOIN bp_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- restrict to plausible systolic BP range to reduce artifacts
    AND ce.valuenum > 10
    AND ce.valuenum < 300
    -- first 48 hours window from ICU intime
    AND ce.charttime >= es.intime
    AND ce.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY es.stay_id
)

SELECT
  COUNTIF(mean_sbp <= 140) AS stays_leq_140,
  COUNT(*) AS total_stays_in_cohort,
  ROUND(100.0 * COUNTIF(mean_sbp <= 140) / COUNT(*), 2) AS percentile_of_140
FROM bp_first48;