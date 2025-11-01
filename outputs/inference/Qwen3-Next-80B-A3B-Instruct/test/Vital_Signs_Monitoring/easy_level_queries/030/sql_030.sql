WITH first_hr_per_stay AS (
  SELECT 
    i.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i ON p.subject_id = i.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce ON i.stay_id = ce.stay_id
    INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND LOWER(di.label) IN ('heart rate', 'hr')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 250  -- reasonable physiological range
    AND ce.charttime >= i.intime  -- ensure measurement is during ICU stay
  GROUP BY 
    i.stay_id
),
first_hr_values AS (
  SELECT 
    ce.valuenum AS first_heart_rate
  FROM 
    first_hr_per_stay f
    INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce 
      ON f.stay_id = ce.stay_id AND f.first_charttime = ce.charttime
    INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di ON ce.itemid = di.itemid
  WHERE 
    LOWER(di.label) IN ('heart rate', 'hr')
    AND ce.valuenum BETWEEN 20 AND 250
)
SELECT 
  MIN(first_heart_rate) AS min_first_heart_rate
FROM 
  first_hr_values;