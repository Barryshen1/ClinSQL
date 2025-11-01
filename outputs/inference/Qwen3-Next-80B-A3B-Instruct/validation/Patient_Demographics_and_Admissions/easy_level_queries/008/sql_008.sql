WITH first_pci AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY pi.chartdate) AS pci_seq
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
    ON p.subject_id = pi.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON pi.hadm_id = a.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (
      LOWER(dip.long_title) LIKE '%percutaneous coronary intervention%'
      OR LOWER(dip.long_title) LIKE '%angioplasty%'
      OR LOWER(dip.long_title) LIKE '%stent%'
      OR LOWER(dip.long_title) LIKE '%coronary revascularization%'
    )
),
readmission AS (
  SELECT 
    fp.subject_id,
    fp.hadm_id AS index_hadm_id,
    fp.dischtime,
    a2.hadm_id AS readmit_hadm_id,
    a2.admittime AS readmit_time,
    CASE 
      WHEN a2.admittime BETWEEN fp.dischtime AND DATE_ADD(fp.dischtime, INTERVAL 30 DAY) 
      THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM 
    first_pci fp
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a2
    ON fp.subject_id = a2.subject_id
  WHERE 
    fp.pci_seq = 1  -- Only first PCI
    AND a2.hadm_id != fp.hadm_id  -- Exclude the index admission
)
SELECT 
  AVG(readmitted_30d) AS avg_30day_readmission_rate
FROM 
  readmission;