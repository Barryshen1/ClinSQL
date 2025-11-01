WITH respiratory_rate AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  WHERE 
    ce.itemid = 220210  
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY 
    ce.stay_id
),
eligible_stays AS (
  SELECT 
    icu.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
avg_rr_eligible AS (
  SELECT 
    rr.avg_rr
  FROM 
    respiratory_rate rr
  INNER JOIN 
    eligible_stays es ON rr.stay_id = es.stay_id
),
percentile_calc AS (
  SELECT 
    avg_rr,
    PERCENT_RANK() OVER (ORDER BY avg_rr) AS pr
  FROM 
    avg_rr_eligible
)
SELECT 
  (SELECT pr * 100 FROM percentile_calc WHERE avg_rr <= 12 ORDER BY avg_rr DESC LIMIT 1) AS percentile_rank_lower,
  (SELECT pr * 100 FROM percentile_calc WHERE avg_rr >= 12 ORDER BY avg_rr LIMIT 1) AS percentile_rank_upper;