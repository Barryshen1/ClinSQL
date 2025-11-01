WITH 
  -- Define respiratory rate itemid
  respiratory_rate_item AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label LIKE '%Respiratory Rate%'
  ),
  
  -- Calculate ICU day and filter data
  icu_data AS (
    SELECT 
      c.subject_id,
      c.hadm_id,
      c.stay_id,
      c.charttime,
      c.valuenum,
      icu.intime,
      DATE_DIFF(c.charttime, icu.intime, 'day') AS icu_day
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON c.subject_id = icu.subject_id AND c.hadm_id = icu.hadm_id AND c.stay_id = icu.stay_id
    WHERE 
      c.itemid IN (SELECT itemid FROM respiratory_rate_item)
      AND c.valuenum IS NOT NULL
  )

SELECT 
  MAX(id.valuenum) AS max_respiratory_rate
FROM 
  icu_data id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON id.subject_id = p.subject_id
WHERE 
  id.icu_day >= 2
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 52 AND 62;