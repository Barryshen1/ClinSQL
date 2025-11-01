WITH target_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.hadm_id,
    i.intime AS icu_intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age BETWEEN 38 AND 48
),
first_heart_rate AS (
  SELECT 
    tp.stay_id,
    MIN(ce.valuenum) AS first_hr
  FROM 
    target_patients tp
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    tp.stay_id = ce.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.label = 'Heart Rate'
    AND ce.charttime = (
      SELECT MIN(charttime)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce2
      WHERE ce2.stay_id = ce.stay_id
        AND ce2.itemid = ce.itemid
    )
  GROUP BY 
    tp.stay_id
)
SELECT 
  MIN(first_hr) AS min_first_heart_rate
FROM 
  first_heart_rate;