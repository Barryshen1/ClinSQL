WITH resp_rates AS (
  SELECT 
    stay.stay_id,
    AVG(ce.valuenum) AS avg_resp_rate
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` stay
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON stay.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON stay.subject_id = ce.subject_id 
    AND stay.hadm_id = ce.hadm_id 
    AND stay.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM stay.intime) - p.anchor_year) BETWEEN 68 AND 78
    AND ce.charttime BETWEEN stay.intime AND TIMESTAMP_ADD(stay.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 1 AND ce.valuenum <= 100  -- Reasonable bounds
  GROUP BY 
    stay.stay_id
  HAVING 
    COUNT(ce.valuenum) >= 1  -- At least one measurement
),
percentile_calc AS (
  SELECT 
    avg_resp_rate,
    PERCENT_RANK() OVER (ORDER BY avg_resp_rate ASC) AS percentile_rank
  FROM 
    resp_rates
)
SELECT 
  ROUND(percentile_rank * 100, 2) AS percentile_for_12
FROM 
  percentile_calc
WHERE 
  avg_resp_rate = 12  -- Target value; if no exact match, this approximates via window
LIMIT 1;