WITH pci_admissions AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE d.long_title LIKE '%percutaneous transluminal coronary angioplasty%'
     OR p.icd_code LIKE '00.4%'
),
eligible_stays AS (
  SELECT i.stay_id, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN pci_admissions pa
    ON i.hadm_id = pa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON i.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 68 AND 78
    AND i.los IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.5, IGNORE NULLS) OVER() AS median_los_days
FROM eligible_stays
LIMIT 1;