WITH eligible_stays AS (
  SELECT 
    ic.stay_id,
    ic.subject_id,
    ic.intime,
    ic.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
heart_rate_means AS (
  SELECT 
    es.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    es.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN es.intime AND es.outtime
  GROUP BY 
    es.stay_id
  HAVING 
    mean_hr IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(mean_hr, 2)[OFFSET(1)] AS median_mean_hr
FROM 
  heart_rate_means;