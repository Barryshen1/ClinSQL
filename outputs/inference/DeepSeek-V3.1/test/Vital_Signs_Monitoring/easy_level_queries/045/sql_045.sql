WITH resp_rate AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%respiratory rate%'
),
icu_patients AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_resp AS (
  SELECT 
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN resp_rate rr
    ON ce.itemid = rr.itemid
  INNER JOIN icu_patients ip
    ON ce.stay_id = ip.stay_id
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
first_resp_values AS (
  SELECT 
    ce.valuenum AS first_rr_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN resp_rate rr
    ON ce.itemid = rr.itemid
  INNER JOIN first_resp fr
    ON ce.stay_id = fr.stay_id AND ce.charttime = fr.first_charttime
  WHERE ce.valuenum IS NOT NULL
)
SELECT 
  STDDEV(first_rr_value) AS sd_first_respiratory_rate
FROM first_resp_values;