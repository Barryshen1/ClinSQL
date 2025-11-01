WITH valid_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.first_careunit,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND i.first_careunit IN ('Stepdown', 'Intermediate Care Unit')
    AND i.los > 1/24.0  -- Exclude very short stays (<1 hour)
),
dbp_per_stay AS (
  SELECT 
    vs.stay_id,
    vs.hadm_id,
    AVG(ce.valuenum) AS mean_dbp
  FROM 
    valid_stays vs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    vs.subject_id = ce.subject_id
    AND vs.hadm_id = ce.hadm_id
    AND vs.stay_id = ce.stay_id
    AND ce.itemid IN (4046, 220182)  -- DBP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN vs.intime AND vs.outtime
  GROUP BY 
    vs.stay_id, vs.hadm_id
  HAVING 
    COUNT(ce.valuenum) > 0  -- Ensure at least one DBP measurement
)
SELECT 
  PERCENTILE_CONT(0.25, 0) OVER() AS q1,
  PERCENTILE_CONT(0.75, 0) OVER() AS q3,
  PERCENTILE_CONT(0.75, 0) OVER() - PERCENTILE_CONT(0.25, 0) OVER() AS iqr
FROM 
  dbp_per_stay;