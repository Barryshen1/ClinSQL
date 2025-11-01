WITH pci_admissions AS (
  SELECT DISTINCT
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code 
    AND p.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON p.subject_id = pat.subject_id
  WHERE 
    (LOWER(d.long_title) LIKE '%percutaneous coronary intervention%'
     OR LOWER(d.long_title) LIKE '%coronary angioplasty%')
    AND pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM p.chartdate) - pat.anchor_year)) BETWEEN 59 AND 69
)

SELECT 
  MAX(total_icu_los) AS max_icu_los
FROM (
  SELECT 
    pa.hadm_id,
    COALESCE(SUM(i.los), 0) AS total_icu_los
  FROM pci_admissions pa
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pa.hadm_id = i.hadm_id
  GROUP BY pa.hadm_id
);