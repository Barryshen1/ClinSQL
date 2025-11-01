WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    COALESCE(a.edregtime, a.admittime) AS start_time
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Calculate age at admission (year-only approximation)
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
    -- Primary AMI diagnosis (ICD-10 codes I21/I22)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.seq_num = 1
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'  -- Case-insensitive match
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_items ti 
    ON le.itemid = ti.itemid
  INNER JOIN filtered_admissions fa 
    ON le.hadm_id = fa.hadm_id
  WHERE le.charttime >= fa.start_time
    AND le.valuenum IS NOT NULL  -- Exclude non-numeric results
)
SELECT 
  CASE 
    WHEN valuenum <= 14 THEN 'normal'
    WHEN valuenum <= 28 THEN 'borderline'  -- 14 < valuenum <= 28
    ELSE 'elevated'
  END AS category,
  COUNT(*) AS count
FROM first_troponin
WHERE rn = 1  -- Only first measurement per admission
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    ELSE 3 
  END;