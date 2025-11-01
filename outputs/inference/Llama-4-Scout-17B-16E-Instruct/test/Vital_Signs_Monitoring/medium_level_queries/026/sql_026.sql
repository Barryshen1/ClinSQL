WITH 
  -- Filter patients by age and gender
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 68 AND 78
  ),

  -- Select relevant ICU stays
  icu_stays AS (
    SELECT stay_id, subject_id, intime, outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE subject_id IN (SELECT subject_id FROM target_patients)
  ),

  -- Respiratory rate events within the first 48 hours of ICU stay
  respiratory_rates AS (
    SELECT 
      ce.stay_id,
      CASE 
        WHEN di.label = 'Respiratory Rate' THEN ce.valuenum
      END AS respiratory_rate
    FROM 
      `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN 
      `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    WHERE 
      ce.stay_id IN (SELECT stay_id FROM icu_stays)
      AND di.label = 'Respiratory Rate'
      AND ce.charttime BETWEEN (SELECT intime FROM icu_stays WHERE stay_id = ce.stay_id) 
                             AND TIMESTAMP_ADD((SELECT intime FROM icu_stays WHERE stay_id = ce.stay_id), INTERVAL 48 HOUR)
  ),

  -- Calculate average respiratory rate per stay
  avg_respiratory_rates AS (
    SELECT stay_id, AVG(respiratory_rate) AS avg_rate
    FROM respiratory_rates
    WHERE respiratory_rate IS NOT NULL
    GROUP BY stay_id
  )

SELECT 
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_rate <= 12 THEN 1 ELSE 0 END) AS stays_below_12,
  (SUM(CASE WHEN avg_rate <= 12 THEN 1 ELSE 0 END) * 1.0 / COUNT(*)) * 100 AS percentile_12
FROM 
  avg_respiratory_rates;