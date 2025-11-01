WITH first_spo2 AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ce.subject_id = p.subject_id
  WHERE di.label = 'SpO2'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND ce.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ce.stay_id 
    ORDER BY ce.charttime
  ) = 1
)
SELECT 
  STDDEV(spo2_value) AS spo2_std_dev
FROM first_spo2;