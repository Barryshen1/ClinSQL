WITH population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 73 AND 83
),

respiratory_events_icu AS (
  SELECT 
    ce.subject_id, 
    ce.hadm_id, 
    ce.charttime,
    ce.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE di.label LIKE '%respiratory rate%' 
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 100
),

respiratory_events_hosp AS (
  SELECT 
    o.subject_id, 
    o.chartdate,
    TIMESTAMP(DATE(o.chartdate)) AS charttime,  -- Fixed: removed invalid second argument
    CAST(o.result_value AS FLOAT64) AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_hosp.omr` o
  WHERE o.result_name LIKE '%respiratory rate%' 
    AND o.result_value IS NOT NULL
    AND CAST(o.result_value AS FLOAT64) > 0
    AND CAST(o.result_value AS FLOAT64) < 100
),

respiratory_events_hosp_with_hadm AS (
  SELECT 
    o.subject_id,
    p.hadm_id,
    o.charttime,
    o.respiratory_rate
  FROM respiratory_events_hosp o
  INNER JOIN population p 
    ON o.subject_id = p.subject_id
    AND o.chartdate BETWEEN DATE(p.admittime) AND DATE(p.dischtime)
),

all_respiratory_events AS (
  SELECT * FROM respiratory_events_icu
  UNION ALL
  SELECT * FROM respiratory_events_hosp_with_hadm
),

first_rr_per_admission AS (
  SELECT 
    re.subject_id,
    re.hadm_id,
    re.charttime,
    re.respiratory_rate
  FROM all_respiratory_events re
  INNER JOIN population p 
    ON re.hadm_id = p.hadm_id
  WHERE re.charttime >= p.admittime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY re.hadm_id ORDER BY re.charttime) = 1
)

SELECT STDDEV(respiratory_rate) AS sd_respiratory_rate
FROM first_rr_per_admission;