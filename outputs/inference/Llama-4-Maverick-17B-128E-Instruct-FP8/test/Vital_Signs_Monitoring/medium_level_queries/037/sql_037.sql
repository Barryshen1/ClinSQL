WITH 
-- Filter female patients aged 88-98
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, ic.stay_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ic ON p.subject_id = ic.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 88 AND 98
),

-- Identify patients on high-flow nasal cannula
hfnc_patients AS (
  SELECT DISTINCT ce.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%High Flow Nasal Cannula%' OR di.label LIKE '%HFNC%'
),

-- Get GCS total scores on or after ICU day 2
gcs_scores AS (
  SELECT ce.valuenum, ce.charttime, ep.stay_id, ep.intime
  FROM eligible_patients ep
  JOIN hfnc_patients hfnc ON ep.subject_id = hfnc.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ep.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE (di.label LIKE '%Glasgow Coma Scale%' OR di.label LIKE '%GCS%') 
    AND di.label NOT LIKE '%component%'  -- Assuming this filters to total GCS
    AND TIMESTAMP_DIFF(ce.charttime, ep.intime, DAY) >= 2
    AND ce.valuenum IS NOT NULL
)

-- Calculate median GCS total score
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_gcs
FROM gcs_scores;