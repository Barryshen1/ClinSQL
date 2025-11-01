WITH cohort AS (
  SELECT 
    icu.stay_id,
    p.anchor_age,
    p.gender,
    icu.intime
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND icu.outtime > icu.intime
),

rr_item AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE label = 'RR'
),

rr_first48 AS (
  SELECT 
    ce.stay_id,
    ce.valuenum
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN 
    cohort c
    ON ce.stay_id = c.stay_id
  JOIN 
    rr_item ri
    ON ce.itemid = ri.itemid
  WHERE 
    ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= c.intime + INTERVAL 48 HOUR
),

avg_rr_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_rr
  FROM 
    rr_first48
  GROUP BY 
    stay_id
),

categorized AS (
  SELECT 
    stay_id,
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr <= 20 THEN '12–20'
      WHEN avg_rr >= 21 AND avg_rr <= 29 THEN '21–29'
      WHEN avg_rr >= 30 THEN '≥30'
    END AS rr_category
  FROM 
    avg_rr_per_stay
)

SELECT 
  rr_category,
  COUNT(*) AS n,
  AVG(avg_rr) AS mean,
  APPROX_QUANTILES(avg_rr, 4)[OFFSET(2)] AS median,
  APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(avg_rr, 4)[OFFSET(3)] - APPROX_QUANTILES(avg_rr, 4)[OFFSET(1)] AS iqr
FROM 
  categorized
GROUP BY 
  rr_category
ORDER BY
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12–20' THEN 2
    WHEN '21–29' THEN 3
    WHEN '≥30' THEN 4
  END;