WITH pci_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    REGEXP_CONTAINS(LOWER(long_title), r'percutaneous(\s+coronary)?\s+intervention') OR
    REGEXP_CONTAINS(LOWER(long_title), r'pci')
),
first_pci AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id 
      ORDER BY a.admittime
    ) AS admission_rank
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN pci_codes pc
    ON p.icd_code = pc.icd_code 
    AND p.icd_version = pc.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.hadm_id = a.hadm_id
),
cohort AS (
  SELECT 
    fp.subject_id, 
    fp.hadm_id, 
    fp.admittime, 
    fp.dischtime,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    -- Calculate age at index admission
    pt.anchor_age + (EXTRACT(YEAR FROM fp.admittime) - pt.anchor_year) AS age_at_admission
  FROM first_pci fp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON fp.subject_id = pt.subject_id
  WHERE 
    fp.admission_rank = 1  -- First PCI
    AND pt.gender = 'M'
    AND (pt.anchor_age + (EXTRACT(YEAR FROM fp.admittime) - pt.anchor_year)) BETWEEN 52 AND 62
    AND fp.hospital_expire_flag = 0  -- Exclude in-hospital deaths
),
readmission_flags AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    -- Flag readmissions within 30 days (excludes index admission)
    MAX(CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
    AND a.admittime > c.dischtime  -- After index discharge
    AND a.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)  -- Within 30 days
    AND a.hadm_id != c.hadm_id     -- Different admission
  GROUP BY c.subject_id, c.hadm_id
)
SELECT 
  AVG(readmitted_30d) * 100 AS avg_30d_readmission_rate
FROM readmission_flags;