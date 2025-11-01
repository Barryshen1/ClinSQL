WITH female_icu_stays AS (
  SELECT 
    p.subject_id, 
    i.stay_id, 
    i.hadm_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
),
first_abg_ph AS (
  SELECT 
    f.subject_id,
    f.stay_id,
    c.valuenum AS ph
  FROM female_icu_stays f
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON f.subject_id = c.subject_id 
    AND f.stay_id = c.stay_id
  WHERE c.itemid = 220045
    AND c.charttime >= f.intime
    AND c.charttime <= TIMESTAMP_ADD(f.intime, INTERVAL 1 DAY)
    AND c.valuenum IS NOT NULL
    AND c.valuenum > 0
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY f.stay_id 
    ORDER BY c.charttime ASC
  ) = 1
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ph) AS median_ph
FROM first_abg_ph;