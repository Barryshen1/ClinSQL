WITH 
-- Identify male patients aged 40-50
patients_info AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    p.anchor_age, 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 40 AND 50
),

-- Extract ICU stay information and join with patients_info
icu_stay AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    patients_info p 
  ON i.subject_id = p.subject_id AND i.hadm_id = p.hadm_id
),

-- Extract SBP values within the first 48 hours of ICU stay
sbp_values AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
  ON ce.itemid = di.itemid
  JOIN 
    icu_stay ic 
  ON ce.stay_id = ic.stay_id
  WHERE 
    di.label = 'Systolic Blood Pressure' 
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),

-- Calculate mean SBP for each stay and categorize
stay_sbp_categories AS (
  SELECT 
    stay_id,
    AVG(sbp) AS mean_sbp,
    CASE 
      WHEN AVG(sbp) < 140 THEN '<140'
      WHEN AVG(sbp) BETWEEN 140 AND 159 THEN '140–159'
      WHEN AVG(sbp) >= 160 THEN '≥160'
    END AS sbp_category
  FROM 
    sbp_values
  GROUP BY 
    stay_id
),

-- Identify MI events per stay
mi_events AS (
  SELECT 
    i.stay_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN 
    icu_stay i 
  ON d.subject_id = i.subject_id AND d.hadm_id = i.hadm_id
  WHERE 
    d.icd_code LIKE '410%'
)

-- Calculate percentages and MI rates per category
SELECT 
  s.sbp_category,
  COUNT(DISTINCT s.stay_id) AS stays_in_category,
  SUM(CASE WHEN s.stay_id IN (SELECT stay_id FROM mi_events) THEN 1 ELSE 0 END) AS mi_events_in_category,
  COUNT(DISTINCT s.stay_id) / (SELECT COUNT(DISTINCT stay_id) FROM icu_stay) * 100 AS percentage_in_category,
  SUM(CASE WHEN s.stay_id IN (SELECT stay_id FROM mi_events) THEN 1 ELSE 0 END) / COUNT(DISTINCT s.stay_id) AS mi_rate_in_category
FROM 
  stay_sbp_categories s
GROUP BY 
  s.sbp_category;