WITH spo2_stays AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    ce.itemid = di.itemid
  WHERE 
    di.label LIKE '%SpO2%'
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.stay_id IS NOT NULL
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) >= 1  -- At least one valid measurement
),
eligible_stays AS (
  SELECT 
    ss.stay_id,
    ss.mean_spo2,
    p.gender,
    EXTRACT(YEAR FROM ic.intime) - p.anchor_age AS age_at_admission
  FROM 
    spo2_stays ss
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  ON 
    ss.stay_id = ic.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM ic.intime) - p.anchor_age) BETWEEN 38 AND 48
)
SELECT 
  ROUND(
    (SUM(CASE WHEN mean_spo2 <= 92 THEN 1.0 ELSE 0 END) / COUNT(*) * 100), 2
  ) AS percentile_92
FROM 
  eligible_stays;