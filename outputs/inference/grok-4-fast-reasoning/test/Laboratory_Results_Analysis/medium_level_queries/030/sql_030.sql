WITH patient_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.gender,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
ami_admissions AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.hadm_id = d.hadm_id
    AND pa.subject_id = d.subject_id
  WHERE pa.age BETWEEN 64 AND 74
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
    AND d.seq_num = 1
),
troponin_events AS (
  SELECT 
    l.hadm_id, 
    l.charttime, 
    l.valuenum,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN ami_admissions aa 
    ON l.hadm_id = aa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON l.hadm_id = a.hadm_id
  WHERE l.itemid = 50315
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
),
index_troponin AS (
  SELECT 
    hadm_id, 
    valuenum AS index_valuenum
  FROM (
    SELECT 
      *,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_events
  )
  WHERE rn = 1
)
SELECT 
  CASE 
    WHEN index_valuenum <= 0.014 THEN 'Normal'
    WHEN index_valuenum <= 0.052 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM index_troponin
GROUP BY 1
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;