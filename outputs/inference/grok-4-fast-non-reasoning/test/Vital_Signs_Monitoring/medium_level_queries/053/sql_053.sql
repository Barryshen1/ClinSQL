WITH eligible_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),
bp_measurements AS (
  SELECT 
    es.stay_id,
    es.intime,
    c.charttime,
    c.valuenum AS sbp
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON es.stay_id = c.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON c.itemid = di.itemid
  WHERE 
    (di.label LIKE '%SBP%' OR di.label LIKE '%Systolic%')
    AND c.valuenum IS NOT NULL
    AND c.charttime >= es.intime
    AND c.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
    AND EXTRACT(HOUR FROM (c.charttime - es.intime)) < 24
)
SELECT 
  CASE 
    WHEN sbp < 140 THEN '<140'
    WHEN sbp >= 140 AND sbp < 160 THEN '140–159'
    ELSE '≥160'
  END AS sbp_category,
  COUNT(*) AS measurement_count,
  AVG(sbp) AS mean_sbp,
  APPROX_QUANTILES(sbp, 4)[OFFSET(2)] AS median_sbp,
  APPROX_QUANTILES(sbp, 4)[OFFSET(3)] - APPROX_QUANTILES(sbp, 4)[OFFSET(1)] AS iqr_sbp
FROM 
  bp_measurements
GROUP BY 
  sbp_category
ORDER BY 
  sbp_category;