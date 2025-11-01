WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 35 AND 45
),
qualifying_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id, ad.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN qualifying_patients qp ON ad.subject_id = qp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON ad.hadm_id = diag.hadm_id AND CAST(diag.seq_num AS STRING) = '1'
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON diag.icd_code = icd.icd_code 
    AND diag.icd_version = icd.icd_version
  WHERE (
    -- Chest pain (ICD-10)
    (diag.icd_version = '10' AND diag.icd_code LIKE 'R07%')
    OR 
    -- AMI (ICD-10)
    (diag.icd_version = '10' AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    OR
    -- AMI (ICD-9, for completeness)
    (diag.icd_version = '9' AND diag.icd_code LIKE '410%')
  )
),
first_troponin AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON le.itemid = dli.itemid
  INNER JOIN qualifying_admissions qa 
    ON le.subject_id = qa.subject_id AND le.hadm_id = qa.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND LOWER(dli.label) LIKE '%troponin t%'
    AND dli.category = 'Chemistry'
    AND le.charttime >= qa.admittime 
    AND le.charttime <= qa.admittime + INTERVAL 1 DAY
)
SELECT 
  CASE 
    WHEN ft.valuenum <= 14 THEN 'Normal'
    WHEN ft.valuenum <= 52 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS troponin_category,
  COUNT(DISTINCT ft.hadm_id) AS admission_count
FROM first_troponin ft
WHERE ft.rn = 1
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
  END;