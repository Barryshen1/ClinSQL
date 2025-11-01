WITH cohort AS (
  -- Step 1: Identify male patients aged 52–62
  SELECT 
    p.subject_id,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' AND
    p.anchor_age BETWEEN 52 AND 62
),

-- Step 2: Identify first PCI procedure per patient
first_pci AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id AS index_hadm_id,
    pc.chartdate AS index_chartdate
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON pc.icd_code = d.icd_code AND pc.icd_version = d.icd_version
  WHERE 
    -- ICD-10 PCS codes for PCI (example range)
    d.icd_code LIKE '0270%' OR
    d.icd_code LIKE '0271%' OR
    d.icd_code LIKE '0272%' OR
    d.icd_code LIKE '0273%'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pc.subject_id ORDER BY pc.chartdate) = 1
),

-- Step 3: Get index admission details
index_admission AS (
  SELECT 
    f.subject_id,
    f.index_hadm_id,
    a.dischtime AS index_dischtime
  FROM 
    first_pci f
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.index_hadm_id = a.hadm_id
  WHERE 
    a.hospital_expire_flag = 0  -- Exclude deaths during index admission
),

-- Step 4: Identify 30-day readmissions
readmissions AS (
  SELECT 
    ia.subject_id,
    ia.index_hadm_id,
    CASE 
      WHEN readmit.hadm_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM 
    index_admission ia
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` readmit
    ON ia.subject_id = readmit.subject_id
    AND readmit.hadm_id != ia.index_hadm_id
    AND readmit.admittime > ia.index_dischtime
    AND readmit.admittime <= DATETIME_ADD(ia.index_dischtime, INTERVAL 30 DAY)
)

-- Final step: Calculate average 30-day readmission rate
SELECT 
  AVG(readmitted_30d) AS avg_30day_readmission_rate
FROM 
  readmissions;