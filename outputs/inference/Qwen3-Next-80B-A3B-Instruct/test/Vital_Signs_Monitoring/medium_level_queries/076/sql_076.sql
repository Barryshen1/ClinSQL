WITH hr_item AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE label = 'Heart Rate'
),
icu_stays_48_58 AS (
  SELECT i.stay_id, i.subject_id, i.intime, i.outtime,
         p.anchor_age
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
    AND p.gender = 'F'
),
hr_48h AS (
  SELECT 
    s.stay_id,
    AVG(ce.valuenum) AS avg_hr_48h
  FROM icu_stays_48_58 s
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON s.stay_id = ce.stay_id
  JOIN hr_item h ON ce.itemid = h.itemid
  WHERE ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY s.stay_id
),
baseline_creatinine AS (
  SELECT 
    s.stay_id,
    MIN(le.valuenum) AS baseline_creatinine
  FROM icu_stays_48_58 s
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON s.subject_id = le.subject_id
  WHERE le.itemid = 50912  -- serum creatinine
    AND le.charttime BETWEEN TIMESTAMP_SUB(s.intime, INTERVAL 7 DAY) AND s.intime
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY s.stay_id
),
creatinine_48h AS (
  SELECT 
    s.stay_id,
    MAX(le.valuenum) AS max_creatinine_48h
  FROM icu_stays_48_58 s
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON s.subject_id = le.subject_id
  WHERE le.itemid = 50912  -- serum creatinine
    AND le.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY s.stay_id
),
aki_status AS (
  SELECT 
    bc.stay_id,
    CASE 
      WHEN cc.max_creatinine_48h >= bc.baseline_creatinine * 1.5 
        OR cc.max_creatinine_48h >= bc.baseline_creatinine + 0.3 
      THEN 1 
      ELSE 0 
    END AS aki_flag
  FROM baseline_creatinine bc
  JOIN creatinine_48h cc ON bc.stay_id = cc.stay_id
),
final_data AS (
  SELECT 
    h.avg_hr_48h,
    a.aki_flag,
    CASE 
      WHEN h.avg_hr_48h < 60 THEN '<60'
      WHEN h.avg_hr_48h BETWEEN 60 AND 99 THEN '60-99'
      WHEN h.avg_hr_48h BETWEEN 100 AND 119 THEN '100-119'
      WHEN h.avg_hr_48h >= 120 THEN '≥120'
    END AS hr_category
  FROM hr_48h h
  JOIN aki_status a ON h.stay_id = a.stay_id
)
SELECT 
  hr_category,
  COUNT(*) AS stay_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_distribution,
  ROUND(AVG(aki_flag) * 100, 2) AS aki_rate_percent
FROM final_data
GROUP BY hr_category
ORDER BY hr_category;