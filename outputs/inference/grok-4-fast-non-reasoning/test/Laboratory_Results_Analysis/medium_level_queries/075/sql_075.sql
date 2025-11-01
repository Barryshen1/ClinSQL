WITH troponin_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
patient_admissions AS (
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND (
      -- Chest pain (ICD-10 R07.*)
      (d.icd_version = '10' AND d.icd_code LIKE 'R07%') OR
      -- AMI (ICD-10 I21.*)
      (d.icd_version = '10' AND d.icd_code LIKE 'I21%') OR
      -- AMI (ICD-9 410.*)
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
    )
),
initial_troponin AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    le.charttime,
    SAFE_CAST(le.valuenum AS FLOAT64) AS valuenum
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
  INNER JOIN troponin_itemids ti
    ON le.itemid = ti.itemid
  WHERE le.valueuom = 'ng/mL'
    AND SAFE_CAST(le.valuenum AS FLOAT64) IS NOT NULL
    AND SAFE_CAST(le.valuenum AS FLOAT64) > 0
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pa.subject_id, pa.hadm_id ORDER BY le.charttime) = 1
),
categorized_troponin AS (
  SELECT 
    *,
    CASE 
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM initial_troponin
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  ROUND(PERCENTILE_CONT(valuenum, 0.5) IGNORE NULLS, 4) AS median,
  ROUND(PERCENTILE_CONT(valuenum, 0.25) IGNORE NULLS, 4) AS q25,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) IGNORE NULLS, 4) AS q75,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) IGNORE NULLS - PERCENTILE_CONT(valuenum, 0.25) IGNORE NULLS, 4) AS iqr
FROM categorized_troponin
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    ELSE 3
  END;