WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    icu.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pat.subject_id = icu.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
),

spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) = 'spo2'
),

spo2_values AS (
  SELECT 
    c.stay_id,
    ce.valuenum
  FROM 
    cohort c
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  INNER JOIN 
    spo2_items s
    ON ce.itemid = s.itemid
  WHERE 
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
),

mean_spo2_per_stay AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM 
    spo2_values
  GROUP BY 
    stay_id
),

percentiles AS (
  SELECT 
    APPROX_QUANTILES(mean_spo2, 100) AS quantiles
  FROM 
    mean_spo2_per_stay
)

SELECT 
  (
    SELECT 
      CAST(SUM(CASE WHEN q <= 92 THEN 1 ELSE 0 END) AS FLOAT64) / COUNT(*) * 100
    FROM 
      UNNEST((SELECT quantiles FROM percentiles)) AS q
  ) AS percentile_rank_of_92;