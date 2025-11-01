WITH qualifying_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
first_rr AS (
  SELECT 
    qs.stay_id,
    ce.valuenum AS resp_rate
  FROM 
    qualifying_stays qs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    ce.subject_id = qs.subject_id
    AND ce.hadm_id = qs.hadm_id
    AND ce.stay_id = qs.stay_id
    AND ce.itemid = 618
    AND ce.charttime >= qs.intime
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY qs.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT 
  APPROX_QUANTILES(resp_rate, 4)[OFFSET(1)] AS p25_first_respiratory_rate
FROM 
  first_rr;