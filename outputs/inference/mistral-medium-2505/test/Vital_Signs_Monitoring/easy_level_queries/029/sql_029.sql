WITH spo2_item AS (
  -- Get the itemid for SpO2 (assuming it's 220277; verify in d_items)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'SpO2'
),

first_spo2 AS (
  -- Get the first SpO2 value for each male patient aged 62-72
  SELECT
    p.subject_id,
    ce.valuenum AS first_spo2_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  JOIN spo2_item si
    ON ce.itemid = si.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100  -- Valid SpO2 range
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) = 1
)

-- Calculate the IQR (25th and 75th percentiles)
SELECT
  PERCENTILE_CONT(first_spo2_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER() - PERCENTILE_CONT(first_spo2_value, 0.25) OVER() AS iqr
FROM first_spo2
LIMIT 1;