WITH valid_bp AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    ce.valuenum AS systolic_bp,
    ce.charttime
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ce.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM ce.charttime) - p.anchor_year BETWEEN 59 AND 69
    AND ce.itemid IN (220045, 220179)  -- Systolic BP itemids
    AND ce.stay_id IS NOT NULL  -- ICU stay
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0  -- Valid positive values
)
SELECT 
  APPROX_QUANTILES(systolic_bp, 4)[OFFSET(3)] AS p75_systolic_bp
FROM 
  valid_bp;