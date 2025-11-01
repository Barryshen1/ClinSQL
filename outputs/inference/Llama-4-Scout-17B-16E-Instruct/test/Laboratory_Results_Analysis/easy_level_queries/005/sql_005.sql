WITH 
  -- Find first serum sodium measurement for each ICU stay
  first_sodium AS (
    SELECT 
      ic.stay_id,
      ic.subject_id,
      ce.valuenum AS sodium_value
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ic.subject_id = ce.subject_id 
        AND ic.hadm_id = ce.hadm_id 
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age >= 89
      AND ce.itemid IN (220050, 220179, 220052, 220180) -- Example itemids for serum sodium
    AND 
      ce.charttime = (SELECT MIN(charttime) 
                      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2 
                      WHERE ce2.subject_id = ic.subject_id 
                        AND ce2.hadm_id = ic.hadm_id 
                        AND ce2.itemid IN (220050, 220179, 220052, 220180))
  )

-- Calculate IQR of first serum sodium
SELECT 
  APPROX_QUANTILES(sodium_value, 1000)[25] AS Q1,
  APPROX_QUANTILES(sodium_value, 1000)[500] AS median,
  APPROX_QUANTILES(sodium_value, 1000)[975] AS Q3,
  APPROX_QUANTILES(sodium_value, 1000)[975] - APPROX_QUANTILES(sodium_value, 1000)[25] AS IQR
FROM 
  first_sodium;