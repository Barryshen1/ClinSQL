WITH pci_admissions AS (
  -- Identify all admissions with PCI procedures
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn_first
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.subject_id = pi.subject_id AND a.hadm_id = pi.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND pi.icd_code LIKE '027%'
    AND pi.icd_version = 'ICD-10'  -- Focus on ICD-10 for modern PCIs
),
index_pci AS (
  -- Select first PCI admission per patient, exclude deaths
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM pci_admissions
  WHERE rn_first = 1
    AND hospital_expire_flag = 0
    AND dischtime IS NOT NULL
),
readmissions AS (
  -- Detect readmissions within 30 days per index admission
  SELECT 
    ip.subject_id,
    ip.hadm_id AS index_hadm_id,
    COUNT(DISTINCT a2.hadm_id) > 0 AS has_readmission
  FROM index_pci ip
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON ip.subject_id = a2.subject_id
    AND a2.hadm_id != ip.hadm_id  -- Exclude index admission
    AND a2.admittime >= ip.dischtime
    AND a2.admittime < DATE_ADD(ip.dischtime, INTERVAL 30 DAY)
  GROUP BY ip.subject_id, ip.hadm_id
)
-- Compute average 30-day readmission rate
SELECT 
  COUNT(*) AS num_patients,
  SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END) AS num_readmitted,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN has_readmission THEN 1 ELSE 0 END), 
      COUNT(*)
    ) * 100, 
    2
  ) AS readmission_rate_percent
FROM readmissions;