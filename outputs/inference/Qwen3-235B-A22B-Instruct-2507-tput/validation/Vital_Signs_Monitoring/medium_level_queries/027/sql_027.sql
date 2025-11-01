WITH female_icu_stays_80_90 AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.icustays i
  ON 
    p.subject_id = i.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
heart_rate_avg_per_stay AS (
  SELECT 
    fis.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM 
    female_icu_stays_80_90 fis
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON 
    fis.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.d_items di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fis.intime
    AND ce.charttime <= fis.outtime
  GROUP BY 
    fis.stay_id
),
percentile_ranks AS (
  SELECT 
    avg_hr,
    PERCENT_RANK() OVER (ORDER BY avg_hr) AS percentile_rank
  FROM 
    heart_rate_avg_per_stay
)
SELECT 
  MAX(CASE WHEN avg_hr <= 110 THEN percentile_rank END) AS percentile_of_110
FROM 
  percentile_ranks;