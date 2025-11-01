WITH resp_rates AS (
  SELECT 
    ce.stay_id,
    MAX(ce.valuenum) AS max_resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Respiratory Rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
eligible_stays AS (
  SELECT 
    ie.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
)
SELECT 
  STDDEV(rr.max_resp_rate) AS sd_max_resp_rate
FROM resp_rates rr
INNER JOIN eligible_stays es 
  ON rr.stay_id = es.stay_id;