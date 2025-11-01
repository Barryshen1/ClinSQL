WITH first_map_per_stay AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    c.valuenum AS map_value,
    c.charttime,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime ASC) AS rn
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents c
    ON i.stay_id = c.stay_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items d
    ON c.itemid = d.itemid
  WHERE 
    d.label = 'MAP'
    AND c.valuenum IS NOT NULL
    AND c.charttime >= i.intime
    AND c.charttime <= i.outtime
),
filtered_patients AS (
  SELECT 
    subject_id,
    anchor_age,
    gender
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients
  WHERE 
    gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
first_map_with_age AS (
  SELECT 
    f.map_value
  FROM 
    first_map_per_stay f
  INNER JOIN 
    filtered_patients fp 
    ON f.subject_id = fp.subject_id
  WHERE 
    f.rn = 1
)
SELECT 
  PERCENTILE_CONT(map_value, 0.25) OVER () AS q1,
  PERCENTILE_CONT(map_value, 0.75) OVER () AS q3,
  PERCENTILE_CONT(map_value, 0.75) OVER () - PERCENTILE_CONT(map_value, 0.25) OVER () AS iqr
FROM 
  first_map_with_age
LIMIT 1;