WITH patients_filtered AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 48 AND 58
),

hr_data AS (
  SELECT 
    pf.stay_id,
    AVG(c.valuenum) AS avg_hr
  FROM patients_filtered pf
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON pf.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE d.label = 'Heart Rate'
    AND c.charttime BETWEEN pf.intime AND DATETIME_ADD(pf.intime, INTERVAL 48 HOUR)
    AND c.valuenum IS NOT NULL
  GROUP BY pf.stay_id
),

baseline_creat AS (
  SELECT 
    pf.stay_id,
    MIN(l.valuenum) AS baseline_creat
  FROM patients_filtered pf
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pf.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE d.label = 'Creatinine' AND d.fluid = 'Blood'
    AND l.charttime BETWEEN pf.intime AND DATETIME_ADD(pf.intime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY pf.stay_id
),

aki_data AS (
  SELECT 
    bc.stay_id,
    MAX(CASE 
          WHEN l.valuenum >= bc.baseline_creat * 1.5 
            OR l.valuenum >= bc.baseline_creat + 0.3 
          THEN 1 ELSE 0 
        END) AS has_aki
  FROM baseline_creat bc
  INNER JOIN patients_filtered pf ON bc.stay_id = pf.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pf.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE d.label = 'Creatinine' AND d.fluid = 'Blood'
    AND l.charttime BETWEEN pf.intime AND pf.outtime
    AND l.valuenum IS NOT NULL
  GROUP BY bc.stay_id
),

combined AS (
  SELECT 
    pf.stay_id,
    hr.avg_hr,
    COALESCE(aki.has_aki, 0) AS has_aki
  FROM patients_filtered pf
  LEFT JOIN hr_data hr ON pf.stay_id = hr.stay_id
  LEFT JOIN aki_data aki ON pf.stay_id = aki.stay_id
  WHERE hr.avg_hr IS NOT NULL
),

categorized AS (
  SELECT
    stay_id,
    avg_hr,
    has_aki,
    CASE 
      WHEN avg_hr < 60 THEN '<60'
      WHEN avg_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN avg_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN avg_hr >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_category
  FROM combined
)

SELECT
  hr_category,
  COUNT(*) AS stay_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_distribution,
  ROUND(AVG(has_aki) * 100, 2) AS aki_rate
FROM categorized
GROUP BY hr_category
ORDER BY 
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
    ELSE 5
  END;