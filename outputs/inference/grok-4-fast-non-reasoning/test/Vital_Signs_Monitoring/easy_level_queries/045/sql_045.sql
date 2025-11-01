WITH first_rr AS (
  SELECT 
    ce.stay_id,
    MIN(ce.valuenum) AS first_respiratory_rate
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON 
    ce.subject_id = icu.subject_id 
    AND ce.hadm_id = icu.hadm_id 
    AND ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    icu.subject_id = p.subject_id
  WHERE 
    di.label LIKE '%Respiratory Rate%'  -- Captures common itemids: 618, 619, 220210
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND ce.charttime >= icu.intime  -- Ensure within stay (though typically true)
  GROUP BY 
    ce.stay_id
  HAVING 
    first_respiratory_rate IS NOT NULL
)
SELECT 
  STDDEV(first_respiratory_rate) AS sd_first_respiratory_rate
FROM 
  first_rr;