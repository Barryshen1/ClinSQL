WITH target_stays AS (
  SELECT 
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 88 AND 98
),
gcs_events AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS gcs
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN target_stays ts
    ON ce.stay_id = ts.stay_id
  WHERE ce.itemid = 226755
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ts.intime + INTERVAL 48 HOUR
),
hf_events AS (
  SELECT 
    stay_id,
    charttime,
    valuenum AS hf_flow
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 227194
    AND valuenum IS NOT NULL
    AND stay_id IN (SELECT stay_id FROM target_stays)
),
combined AS (
  SELECT 
    ge.stay_id,
    ge.charttime,
    ge.gcs,
    hf.hf_flow,
    ROW_NUMBER() OVER (
      PARTITION BY ge.stay_id, ge.charttime 
      ORDER BY hf.charttime DESC
    ) AS rn
  FROM gcs_events ge
  LEFT JOIN hf_events hf
    ON ge.stay_id = hf.stay_id
    AND hf.charttime <= ge.charttime
)
SELECT 
  APPROX_QUANTILES(gcs, 100)[SAFE_OFFSET(50)] AS median_gcs
FROM combined
WHERE rn = 1 AND hf_flow > 0;