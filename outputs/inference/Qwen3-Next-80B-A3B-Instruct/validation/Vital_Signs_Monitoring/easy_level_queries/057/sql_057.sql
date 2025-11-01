WITH respiratory_rates AS (
  SELECT 
    i.stay_id,
    MAX(c.valuenum) AS max_respiratory_rate
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND d.label = 'Respiratory Rate'
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
    AND c.valuenum < 100  -- reasonable physiological range
  GROUP BY 
    i.stay_id
)
SELECT 
  MIN(max_respiratory_rate) AS minimum_of_maximum_respiratory_rate
FROM 
  respiratory_rates;