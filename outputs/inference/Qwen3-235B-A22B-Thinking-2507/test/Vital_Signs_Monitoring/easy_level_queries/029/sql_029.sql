WITH filtered_spo2 AS (
  SELECT 
    ce.subject_id,
    ce.charttime,
    ce.valuenum AS spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE ce.itemid = 220277  -- Standard SpO2 itemid
    AND p.gender = 'M'
    AND ce.valuenum IS NOT NULL
    AND (p.anchor_age + (EXTRACT(YEAR FROM ce.charttime) - p.anchor_year)) BETWEEN 62 AND 72
),
first_spo2 AS (
  SELECT 
    subject_id,
    spo2_value,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY charttime) AS rn
  FROM filtered_spo2
),
first_values AS (
  SELECT spo2_value
  FROM first_spo2
  WHERE rn = 1
)
SELECT 
  q1,
  q3,
  q3 - q1 AS iqr
FROM (
  SELECT 
    PERCENTILE_CONT(spo2_value, 0.25) OVER () AS q1,
    PERCENTILE_CONT(spo2_value, 0.75) OVER () AS q3
  FROM first_values
  LIMIT 1
);