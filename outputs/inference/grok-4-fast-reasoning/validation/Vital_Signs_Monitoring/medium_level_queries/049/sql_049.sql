WITH qualifying_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
avg_sbp_per_stay AS (
  SELECT 
    qs.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM 
    qualifying_stays qs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    ce.stay_id = qs.stay_id
  WHERE 
    ce.itemid IN (220045, 220179)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= qs.intime
    AND ce.charttime <= DATETIME_ADD(qs.intime, INTERVAL 2 DAY)
  GROUP BY 
    qs.stay_id
  HAVING 
    AVG(ce.valuenum) IS NOT NULL  -- Ensures only stays with measurements
)
SELECT 
  100.0 * COUNTIF(avg_sbp <= 130) / COUNT(*) AS percentile
FROM 
  avg_sbp_per_stay;