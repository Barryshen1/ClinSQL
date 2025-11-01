WITH resp_rates AS (
  SELECT 
    c.stay_id,
    AVG(c.valuenum) AS mean_rr
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.subject_id = i.subject_id 
    AND c.hadm_id = i.hadm_id 
    AND c.stay_id = i.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_age) BETWEEN 39 AND 49
    AND d.label = 'Respiratory Rate'
    AND c.valuenum BETWEEN 0 AND 100
    AND i.intime <= c.charttime 
    AND c.charttime <= i.outtime
    AND i.los >= (1.0 / 24.0)  -- los >= 1 hour
  GROUP BY 
    c.stay_id
  HAVING 
    COUNT(c.valuenum) >= 5  -- at least 5 measurements per stay
)
SELECT 
  APPROX_QUANTILES(mean_rr, 4)[OFFSET(3)] AS p75_mean_respiratory_rate
FROM 
  resp_rates;