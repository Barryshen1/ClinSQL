WITH respiratory_max_per_patient AS (
  SELECT 
    p.subject_id,
    MAX(ce.valuenum) AS max_respiratory_rate
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON ce.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND di.label = 'Respiratory Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 5 
    AND ce.valuenum < 60
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV_POP(max_respiratory_rate) AS sd_max_respiratory_rate
FROM 
  respiratory_max_per_patient;