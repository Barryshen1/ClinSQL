WITH stays AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year AS age_at_stay
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + EXTRACT(YEAR FROM s.intime) - p.anchor_year BETWEEN 48 AND 58
),
hr_data AS (
  SELECT 
    st.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM stays st
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = st.stay_id
  WHERE ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= st.intime
    AND ce.charttime <= TIMESTAMP_ADD(st.intime, INTERVAL 48 HOUR)
  GROUP BY st.stay_id
  HAVING AVG(ce.valuenum) IS NOT NULL
),
creat_events AS (
  SELECT 
    st.stay_id,
    le.charttime,
    le.valuenum
  FROM stays st
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.subject_id = st.subject_id 
    AND le.hadm_id = st.hadm_id
  WHERE le.itemid = 50912
    AND le.valuenum IS NOT NULL 
    AND le.valuenum > 0
    AND le.charttime >= st.intime
    AND le.charttime <= TIMESTAMP_ADD(st.intime, INTERVAL 48 HOUR)
),
baseline AS (
  SELECT 
    stay_id, 
    baseline_creat
  FROM (
    SELECT 
      stay_id, 
      valuenum AS baseline_creat,
      ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY charttime ASC) AS rn
    FROM creat_events
  ) 
  WHERE rn = 1
),
peak AS (
  SELECT 
    stay_id, 
    MAX(valuenum) AS peak_creat
  FROM creat_events
  GROUP BY stay_id
),
total_stays AS (
  SELECT COUNT(*) AS tot FROM hr_data
),
main AS (
  SELECT 
    h.stay_id,
    h.avg_hr,
    CASE 
      WHEN h.avg_hr < 60 THEN '<60'
      WHEN h.avg_hr < 100 THEN '60-99'
      WHEN h.avg_hr < 120 THEN '100-119'
      ELSE '>=120'
    END AS hr_category,
    CASE 
      WHEN b.baseline_creat IS NOT NULL 
        AND (p.peak_creat >= b.baseline_creat * 1.5 
             OR (p.peak_creat - b.baseline_creat) >= 0.3) THEN 1
      ELSE 0 
    END AS aki_flag
  FROM hr_data h
  LEFT JOIN baseline b ON h.stay_id = b.stay_id
  LEFT JOIN peak p ON h.stay_id = p.stay_id
)
SELECT 
  hr_category,
  COUNT(stay_id) AS n_stays,
  ROUND(COUNT(stay_id) * 100.0 / (SELECT tot FROM total_stays), 1) AS percent_distribution,
  ROUND(SUM(aki_flag) * 100.0 / COUNT(stay_id), 1) AS aki_rate
FROM main
GROUP BY hr_category
ORDER BY 
  CASE hr_category 
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;