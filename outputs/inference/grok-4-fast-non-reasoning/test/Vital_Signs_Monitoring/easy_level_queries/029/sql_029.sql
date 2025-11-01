WITH first_spo2 AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    ce.valuenum AS first_spo2_value
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE 
    ce.itemid = 220277  -- SpO2
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.charttime >= icu.intime  -- Ensure after ICU admission
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY first_spo2_value) -
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY first_spo2_value) AS iqr_spo2
FROM first_spo2;