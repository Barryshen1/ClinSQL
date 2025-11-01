WITH first_spo2 AS (
  SELECT 
    i.stay_id,
    c.valuenum AS spo2_value,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  JOIN physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND d.label = 'SpO2'
    AND c.valuenum IS NOT NULL
    AND c.valuenum >= 0
    AND c.valuenum <= 100
),
first_spo2_filtered AS (
  SELECT spo2_value
  FROM first_spo2
  WHERE rn = 1
)
SELECT 
  PERCENTILE_CONT(spo2_value, 0.75) OVER () - PERCENTILE_CONT(spo2_value, 0.25) OVER () AS iqr_spo2
FROM first_spo2_filtered
LIMIT 1;