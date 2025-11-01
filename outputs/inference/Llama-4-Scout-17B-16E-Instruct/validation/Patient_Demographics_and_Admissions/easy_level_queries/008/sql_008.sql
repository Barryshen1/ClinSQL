WITH 
-- Identify patients who underwent PCI
pci_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` icd ON a.hadm_id = icd.hadm_id
  WHERE p.anchor_age BETWEEN 52 AND 62
  AND p.gender = 'M'
  AND icd.icd_code LIKE '36%'  -- PCI procedure code
  AND icd.seq_num = 1  -- First PCI
),

-- Identify readmissions within 30 days
readmissions AS (
  SELECT a1.subject_id, a2.admittime, a1.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE a1.dischtime IS NOT NULL
  AND a2.admittime BETWEEN TIMESTAMP_ADD(a1.dischtime, INTERVAL 0 DAY) AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  AND a1.hadm_id < a2.hadm_id  -- Ensure it's a readmission
)

-- Calculate readmission rate
SELECT 
  COUNT(DISTINCT CASE WHEN rp.subject_id IS NOT NULL THEN rp.subject_id END) / COUNT(DISTINCT pp.subject_id) AS readmission_rate
FROM pci_patients pp
LEFT JOIN readmissions rp ON pp.subject_id = rp.subject_id;