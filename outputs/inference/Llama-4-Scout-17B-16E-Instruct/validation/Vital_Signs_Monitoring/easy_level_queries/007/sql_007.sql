WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id, anchor_age
    FROM physionet-data.mimiciv_3_1_hosp.patients
    WHERE anchor_age BETWEEN 73 AND 83 AND gender = 'F'
  ),

  -- Identify respiratory rate itemid
  respiratory_rate_item AS (
    SELECT itemid
    FROM physionet-data.mimiciv_3_1_icu.d_items
    WHERE label LIKE '%Respiratory Rate%'
  ),

  -- Get first recorded respiratory rate for each patient
  first_respiratory_rate AS (
    SELECT 
      ce.subject_id,
      ce.valuenum AS respiratory_rate
    FROM 
      physionet-data.mimiciv_3_1_icu.chartevents ce
    JOIN 
      respiratory_rate_item rri ON ce.itemid = rri.itemid
    JOIN 
      physionet-data.mimiciv_3_1_icu.icustays icu ON ce.subject_id = icu.subject_id AND ce.hadm_id = icu.hadm_id
    WHERE 
      ce.valuenum IS NOT NULL
      AND ce.charttime = (SELECT MIN(charttime) FROM physionet-data.mimiciv_3_1_icu.chartevents ce2 
                          WHERE ce2.subject_id = ce.subject_id AND ce2.hadm_id = ce.hadm_id AND ce2.itemid = rri.itemid)
  )

-- Calculate standard deviation of the first recorded respiratory rate
SELECT 
  STDDEV(respiratory_rate) AS std_dev
FROM 
  first_respiratory_rate
  JOIN target_patients tp ON first_respiratory_rate.subject_id = tp.subject_id;