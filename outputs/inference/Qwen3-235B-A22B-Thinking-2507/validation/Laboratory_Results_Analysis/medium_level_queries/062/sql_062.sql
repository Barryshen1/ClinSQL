WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 46 AND 56
),
first_tnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY l.hadm_id 
      ORDER BY l.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN eligible_admissions e
    ON l.hadm_id = e.hadm_id
  WHERE l.itemid = 50359  -- hs-TnT
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT 
    e.hadm_id,
    e.admittime,
    e.dischtime,
    CASE 
      WHEN f.valuenum < 14 THEN 'Normal'
      WHEN f.valuenum BETWEEN 14 AND 59 THEN 'Borderline'
      WHEN f.valuenum >= 60 THEN 'Myocardial Injury'
    END AS category
  FROM eligible_admissions e
  INNER JOIN first_tnt f
    ON e.hadm_id = f.hadm_id
  WHERE f.rn = 1
)
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400), 2) AS mean_los_days
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;