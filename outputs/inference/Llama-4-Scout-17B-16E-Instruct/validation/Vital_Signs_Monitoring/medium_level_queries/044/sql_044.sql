WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 81 AND 91
),
icu_stays AS (
  SELECT 
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    patient_info p ON i.subject_id = p.subject_id
),
sbp_events AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    di.label LIKE '%Systolic Blood Pressure%' 
    AND ce.valuenum IS NOT NULL
),
filtered_sbp_events AS (
  SELECT 
    stay_id,
    charttime,
    valuenum
  FROM 
    sbp_events
  WHERE 
    (stay_id, charttime) IN (
      SELECT 
        stay_id,
        charttime
      FROM 
        icu_stays i
      JOIN 
        sbp_events s ON i.stay_id = s.stay_id
      WHERE 
        s.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
    )
),
avg_sbp AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM 
    filtered_sbp_events
  GROUP BY 
    stay_id
)
SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_sbp) AS median,
  COUNTIF(avg_sbp <= 150) * 1.0 / COUNT(avg_sbp) AS percentile_150
FROM 
  avg_sbp;