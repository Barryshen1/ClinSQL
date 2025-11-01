WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND d.seq_num = 1
    AND d.icd_version = 10
    AND d.icd_code IN ('I200','I210','I211','I212','I213','I214','I219')
    AND a.dischtime IS NOT NULL
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
),
first_tnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE 
    l.itemid = 50341
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT 
    c.hadm_id,
    CASE 
      WHEN f.valuenum <= 14 THEN 'Normal'
      WHEN f.valuenum > 14 AND f.valuenum <= 59 THEN 'Borderline'
      WHEN f.valuenum > 59 THEN 'Myocardial Injury'
    END AS category,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (60*60*24) AS los_days
  FROM cohort c
  INNER JOIN first_tnt f 
    ON c.hadm_id = f.hadm_id AND f.rn = 1
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.hadm_id = a.hadm_id
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(los_days), 2) AS mean_los_days
FROM categorized
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;