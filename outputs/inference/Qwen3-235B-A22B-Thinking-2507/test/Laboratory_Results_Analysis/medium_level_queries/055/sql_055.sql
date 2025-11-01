WITH 
-- Step 1: Get admissions with age and filter by gender and age
admissions_filtered AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
),

-- Step 2: Filter by primary diagnosis (chest pain or AMI)
admissions_diagnosis AS (
  SELECT 
    af.hadm_id,
    af.subject_id,
    af.admittime,
    af.dischtime,
    af.age
  FROM admissions_filtered af
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON af.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE diag.seq_num = 1
    AND (
      d_diag.icd_code IN ('R072','R073','R074','R078','R079') 
      OR d_diag.icd_code LIKE 'I21%' 
      OR d_diag.icd_code LIKE 'I22%'
    )
),

-- Step 3: Get the first hs-TnT for each admission
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  WHERE le.itemid IN (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label = 'Troponin T, high sensitivity'
  )
  AND le.valuenum IS NOT NULL
),

-- Step 4: Join admissions_diagnosis with first_troponin
troponin_with_admission AS (
  SELECT 
    ad.hadm_id,
    ad.admittime,
    ad.dischtime,
    ft.valuenum,
    -- Compute LOS in days (BigQuery-compatible)
    TIMESTAMP_DIFF(ad.dischtime, ad.admittime, SECOND) / (24*60*60) AS los_days
  FROM admissions_diagnosis ad
  INNER JOIN first_troponin ft
    ON ad.hadm_id = ft.hadm_id
  WHERE ft.rn = 1
    -- Ensure lab event is during admission
    AND ft.charttime >= ad.admittime
    AND ft.charttime <= ad.dischtime
)

-- Final aggregation
SELECT
  CASE 
    WHEN valuenum < 14 THEN 'normal'
    WHEN valuenum BETWEEN 14 AND 19 THEN 'borderline'
    WHEN valuenum >= 20 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(los_days) AS mean_los_days
FROM troponin_with_admission
GROUP BY troponin_category
ORDER BY 
  CASE troponin_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial injury' THEN 3
    ELSE 4
  END;