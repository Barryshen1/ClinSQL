WITH first_spo2 AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    FIRST_VALUE(ce.valuenum) OVER (
      PARTITION BY p.subject_id 
      ORDER BY ce.charttime 
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_spo2_value
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON p.subject_id = ce.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 0
    AND ce.valuenum <= 100
  QUALIFY 
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id 
      ORDER BY ce.charttime ASC
    ) = 1  -- Ensures we take the value at the absolute min charttime per patient
)
SELECT 
  PERCENTILE_CONT(first_spo2_value, 0.75) OVER() - PERCENTILE_CONT(first_spo2_value, 0.25) OVER() AS iqr_spo2
FROM first_spo2
WHERE first_spo2_value IS NOT NULL;  -- Final filter for patients with valid first value;