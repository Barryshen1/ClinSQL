WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 73 AND 83
),
respiratory_rate_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Respiratory Rate'
),
first_respiratory_rate AS (
  SELECT 
    ce.subject_id,
    FIRST_VALUE(ce.valuenum) OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) AS first_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  JOIN respiratory_rate_itemid rri ON ce.itemid = rri.itemid
  WHERE ce.subject_id IN (SELECT subject_id FROM patients_filtered)
)
SELECT 
  STDDEV(first_rr) AS sd_first_respiratory_rate
FROM first_respiratory_rate;