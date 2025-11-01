WITH first_spo2 AS (
  SELECT
    c.stay_id,
    c.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE
    d.label = 'SpO2'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN i.intime AND i.outtime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY c.charttime) = 1
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(spo2_value, 0.25) WITHIN GROUP (ORDER BY spo2_value) AS q1,
    PERCENTILE_CONT(spo2_value, 0.75) WITHIN GROUP (ORDER BY spo2_value) AS q3
  FROM first_spo2
)
SELECT q3 - q1 AS iqr
FROM percentiles;