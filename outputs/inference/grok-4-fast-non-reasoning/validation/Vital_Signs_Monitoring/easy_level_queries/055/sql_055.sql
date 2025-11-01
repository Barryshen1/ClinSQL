WITH sbp_data AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ce.subject_id = pat.subject_id
  WHERE 
    -- Location: step-down/IMC units
    icu.first_careunit IN ('Intermediate Care Unit', 'Stepdown Unit')
    -- Demographics
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    -- SBP itemids (non-invasive systolic BP)
    AND ce.itemid IN (220045, 220179)
    -- Valid SBP value
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg'
    -- First 24 hours of ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
)

SELECT 
  STDDEV(sbp) AS sd_sbp
FROM 
  sbp_data;