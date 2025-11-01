WITH first_map AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    c.valuenum AS map_value,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE 
    d.label IN ('Mean Arterial Pressure', 'MAP')  -- Common labels for MAP
    AND c.valuenum IS NOT NULL
    AND c.charttime >= i.intime  -- Only measurements during ICU stay
)
SELECT 
  STDDEV_POP(fm.map_value) AS sd_first_map
FROM 
  first_map fm
INNER JOIN 
  physionet-data.mimiciv_3_1_hosp.patients p
  ON fm.subject_id = p.subject_id
WHERE 
  fm.rn = 1
  AND p.gender = 'M'
  AND p.anchor_age BETWEEN 55 AND 65;