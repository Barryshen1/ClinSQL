WITH mcs_procedures AS (
  SELECT 
    p.subject_id,
    proc.hadm_id,
    proc.icd_code
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON proc.hadm_id = adm.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_icd
    ON proc.icd_code = d_icd.icd_code 
    AND proc.icd_version = d_icd.icd_version
  WHERE 
    p.gender = 1  -- Male (INT64: 1 = M, 0 = F)
    AND CAST(p.anchor_age AS INT64) BETWEEN 80 AND 90
    AND proc.icd_version = '10'
    AND proc.icd_code IN (
      -- IABP
      '02UA0JZ',
      -- LVAD
      '02WA0KZ', 
      -- RVAD
      '02RA0KZ',
      -- ECMO (veno-arterial, central/peripheral)
      '5A02110', '5A0211D'
    )
)

SELECT 
  MAX(mcs_count) AS max_distinct_mcs_procedures
FROM (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS mcs_count
  FROM 
    mcs_procedures
  GROUP BY 
    hadm_id
);