WITH male_icu_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),
map_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS map_value,
    ce.charttime
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%map%'
    AND di.linksto = 'chartevents'
    AND ce.valuenum BETWEEN 20 AND 150
),
map_within_stay AS (
  SELECT 
    m.stay_id,
    m.map_value
  FROM 
    map_measurements m
  INNER JOIN 
    male_icu_patients mip
    ON m.stay_id = mip.stay_id
  WHERE 
    m.charttime >= mip.intime
    AND m.charttime <= mip.outtime
),
avg_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(map_value) AS avg_map
  FROM 
    map_within_stay
  GROUP BY 
    stay_id
)
SELECT 
  COUNT(CASE WHEN avg_map <= 60 THEN 1 END) * 1.0 / NULLIF(COUNT(*), 0) AS percentile_rank
FROM 
  avg_map_per_stay;