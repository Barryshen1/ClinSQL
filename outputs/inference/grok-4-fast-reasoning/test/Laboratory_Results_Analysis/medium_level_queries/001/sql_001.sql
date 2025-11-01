WITH qualifying_admissions AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    p.gender, 
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 'ICD-9' AND d.icd_code LIKE '410%') 
      OR 
      (d.icd_version = 'ICD-10' AND d.icd_code LIKE 'I21%')
    )
),
ages AS (
  SELECT 
    *,
    SAFE_CAST(anchor_age + EXTRACT(YEAR FROM admittime) - anchor_year AS INT64) AS age
  FROM qualifying_admissions
),
filtered_patients AS (
  SELECT *
  FROM ages
  WHERE age BETWEEN 40 AND 50
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime ASC
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN filtered_patients fp 
    ON le.subject_id = fp.subject_id 
    AND le.hadm_id = fp.hadm_id
  WHERE le.itemid = 50586
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.charttime >= fp.admittime
)
SELECT 
  CASE 
    WHEN valuenum <= 0.01 THEN 'normal'
    WHEN valuenum > 0.01 AND valuenum <= 0.1 THEN 'borderline'
    ELSE 'elevated'
  END AS category,
  COUNT(*) AS count
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;