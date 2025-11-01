WITH cohort_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
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
    AND p.anchor_age BETWEEN 35 AND 45
),
resp_rates AS (
  SELECT 
    cs.stay_id,
    ce.charttime,
    ce.valuenum AS resp_rate
  FROM 
    cohort_stays cs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    cs.stay_id = ce.stay_id
  WHERE 
    ce.itemid = 618
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= cs.intime
    AND ce.charttime <= cs.outtime
)
SELECT 
  MIN(max_rr_per_stay) AS min_of_max_respiratory_rate
FROM (
  SELECT 
    stay_id,
    MAX(resp_rate) AS max_rr_per_stay
  FROM 
    resp_rates
  GROUP BY 
    stay_id
);