WITH acs_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.anchor_year, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.hospital_expire_flag = 0
    AND DATE(a.admittime) >= DATE(CAST(p.anchor_year AS STRING) || '-01-01')
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code LIKE '410.%') OR
      (d.icd_version = '10' AND d.icd_code LIKE 'I21%')
    )
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%TroponinT%'
),
initial_troponin AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    le.charttime,
    le.valuenum
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ap.subject_id = le.subject_id AND ap.hadm_id = le.hadm_id
  INNER JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/ml'
    AND le.charttime >= ap.admittime  -- After admission
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY le.charttime ASC) = 1
),
categorized_troponin AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum > 0.01 AND valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM initial_troponin
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percentage
FROM categorized_troponin
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;