WITH 
-- Identify diastolic blood pressure itemids
dbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Diastolic Blood Pressure%'
),

-- Filter relevant patients and stays
relevant_stays AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON s.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),

-- Filter relevant chartevents (noninvasive ventilation and DBP measurements)
relevant_chartevents AS (
  SELECT 
    c.stay_id,
    c.charttime,
    c.valuenum,
    c.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  WHERE 
    c.stay_id IN (SELECT stay_id FROM relevant_stays)
    AND c.itemid IN (SELECT itemid FROM dbp_itemids)
    AND c.valuenum IS NOT NULL
    AND c.valueuom = 'mmHg'
)

-- Calculate 25th percentile of maximum DBP per stay
SELECT 
  APPROX_QUANTILES(max_dbp, 100)[OFFSET(25)] AS percentile_25th
FROM (
  SELECT 
    stay_id,
    MAX(valuenum) AS max_dbp
  FROM 
    relevant_chartevents
  GROUP BY 
    stay_id
);