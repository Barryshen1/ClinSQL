WITH first_icu_stays AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY i.intime) = 1
),
temps AS (
  SELECT 
    valuenum
  FROM 
    first_icu_stays fis
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    fis.subject_id = ce.subject_id
    AND fis.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 676
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fis.intime
    AND ce.charttime < TIMESTAMP_ADD(fis.intime, INTERVAL 24 HOUR)
)
SELECT 
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median_temperature_f
FROM 
  temps;