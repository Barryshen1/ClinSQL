WITH cte1 AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    (di.long_title LIKE '%acute coronary syndrome%' 
     OR di.long_title LIKE '%myocardial infarction%' 
     OR di.long_title LIKE '%unstable angina%')
    AND p.gender = 'M'
    AND (anchor_age + (EXTRACT(YEAR FROM a.admittime) - anchor_year)) BETWEEN 90 AND 100
),
cte2 AS (
  SELECT 
    l.hadm_id, 
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  WHERE 
    di.label LIKE '%Troponin T%'
    AND l.hadm_id IN (SELECT hadm_id FROM cte1)
    AND l.valuenum IS NOT NULL
),
cte3 AS (
  SELECT 
    cte2.hadm_id, 
    cte2.valuenum, 
    cte1.admittime, 
    cte1.dischtime,
    CASE
      WHEN cte2.valuenum < 0.01 THEN 'Normal'
      WHEN cte2.valuenum >= 0.01 AND cte2.valuenum < 0.04 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM cte2
  JOIN cte1 
    ON cte2.hadm_id = cte1.hadm_id
  WHERE cte2.rn = 1
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS mean_los
FROM cte3
GROUP BY troponin_category;