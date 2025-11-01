WITH acs_patients AS (
  -- Filter male patients aged 79-89
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND p.anchor_year = 2008  -- Ensure anchor age applicability
  
  INTERSECT DISTINCT
  
  -- Patients with suspected ACS admission (primary or early seq_num diagnosis)
  SELECT DISTINCT a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE a.admittime >= '2008-01-01'  -- Post-anchor admissions
    AND d.seq_num <= 5  -- Primary or early diagnoses for suspected ACS
    AND (
      -- ICD-9/10 codes for ACS (unstable angina, NSTEMI, STEMI)
      REGEXP_CONTAINS(icd.long_title, r'(acute|myocardial|infarction|angina|coronary|syndrome).*?(unstable|nstemi|stemi|non-st|nontransmural)') 
      OR d.icd_code IN (
        '410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9',  -- STEMI/NSTEMI ICD-9
        '411.1',  -- Unstable angina
        'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',  -- Acute MI ICD-10
        'I25.110'  -- Unstable angina ICD-10
      )
    )
),
first_admission AS (
  -- Get first ACS admission per patient
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN acs_patients ap ON a.subject_id = ap.subject_id
  WHERE a.admittime >= '2008-01-01'
),
initial_troponin AS (
  -- Extract earliest Troponin T within 24h of admission
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY fa.subject_id ORDER BY l.charttime) AS rn  -- Earliest per patient
  FROM first_admission fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON fa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li ON l.itemid = li.itemid
  WHERE l.charttime BETWEEN fa.admittime AND TIMESTAMP_ADD(fa.admittime, INTERVAL 1 DAY)
    AND li.label LIKE '%TROPONIN T%'  -- Matches Troponin T items
    AND l.valuenum IS NOT NULL 
    AND l.valuenum > 0  -- Valid positive values
    AND fa.rn = 1  -- Only first admission
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean_troponin,
  PERCENTILE_CONT(valuenum, 0.5) OVER (PARTITION BY category) AS median_troponin,
  PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY category) AS q1_troponin,
  PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY category) AS q3_troponin,
  ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (PARTITION BY category) - PERCENTILE_CONT(valuenum, 0.25) OVER (PARTITION BY category), 4) AS iqr_troponin
FROM (
  SELECT 
    subject_id,
    valuenum,
    CASE 
      WHEN valuenum <= 0.01 THEN 'normal'
      WHEN valuenum <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM initial_troponin
  WHERE rn = 1  -- Earliest Troponin T per patient
)
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    WHEN 'elevated' THEN 3 
  END;