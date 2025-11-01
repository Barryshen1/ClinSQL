WITH pci_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON a.hadm_id = pi.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    pi.icd_version = 10
    AND pi.icd_code LIKE '021%'  -- ICD-10-PCS codes for PCI
    AND p.gender = 'M'
),
first_pci AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM pci_admissions
),
index_adm AS (
  SELECT 
    fp.subject_id,
    fp.hadm_id,
    fp.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM fp.admittime) - p.anchor_year) AS age
  FROM first_pci fp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON fp.subject_id = p.subject_id
  WHERE 
    fp.rn = 1
    AND p.anchor_age + (EXTRACT(YEAR FROM fp.admittime) - p.anchor_year) BETWEEN 52 AND 62
),
readmission_flag AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
        WHERE 
          a.subject_id = i.subject_id
          AND a.admittime > i.dischtime
          AND a.admittime <= i.dischtime + INTERVAL '30' DAY
          AND a.hadm_id != i.hadm_id
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM index_adm i
)
SELECT 
  AVG(readmitted) AS readmission_rate
FROM readmission_flag;