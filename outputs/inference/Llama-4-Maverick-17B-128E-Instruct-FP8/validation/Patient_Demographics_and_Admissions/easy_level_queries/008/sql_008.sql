WITH 
-- Step 1: Identify male patients aged 52-62
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 52 AND 62
),

-- Step 2: Identify patients with PCI
pci_patients AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p 
    ON e.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Percutaneous transluminal coronary angioplasty%'
     OR d.long_title LIKE '%Percutaneous coronary intervention%'
),

-- Step 3: Identify first PCI admission for each patient
first_pci_admission AS (
  SELECT subject_id, MIN(hadm_id) AS hadm_id
  FROM pci_patients
  GROUP BY subject_id
),

-- Step 4: Calculate 30-day readmission rate
readmissions AS (
  SELECT 
    fpa.subject_id,
    a.hadm_id,
    a.admittime,
    LAG(a.dischtime) OVER (PARTITION BY fpa.subject_id ORDER BY a.admittime) AS prev_dischtime
  FROM first_pci_admission fpa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON fpa.subject_id = a.subject_id
  WHERE a.hadm_id != fpa.hadm_id  -- Exclude the index admission
)

SELECT 
  AVG(CASE WHEN DATETIME_DIFF(admittime, prev_dischtime, DAY) <= 30 THEN 1 ELSE 0 END) AS avg_30day_readmission_rate
FROM readmissions
WHERE prev_dischtime IS NOT NULL;  -- Ensure we're comparing valid discharge dates;