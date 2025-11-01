WITH filtered_icu_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 63 AND 73
),
respiratory_rates AS (
  SELECT 
    ce.subject_id,
    ce.valuenum AS resp_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.stay_id IN (SELECT stay_id FROM filtered_icu_stays)
),
patient_max_resp AS (
  SELECT 
    subject_id,
    MAX(resp_rate) AS max_resp_rate
  FROM respiratory_rates
  GROUP BY subject_id
)
SELECT 
  STDDEV(max_resp_rate) AS sd_max_resp_rate
FROM patient_max_resp;