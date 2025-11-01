WITH dialysis_admissions AS (
  SELECT DISTINCT p.subject_id, p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    (d.icd_code LIKE '39.95' AND d.icd_version = 9) OR
    (d.icd_code LIKE '54.98' AND d.icd_version = 9) OR
    (d.icd_code LIKE '5A1D%' AND d.icd_version = 10) OR
    (d.icd_code LIKE '3E1M%' AND d.icd_version = 10)
),
first_icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    los,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS stay_seq
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS q25,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS q75,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] - APPROX_QUANTILES(los, 100)[OFFSET(25)] AS iqr
FROM first_icu_stay fis
INNER JOIN dialysis_admissions da
  ON fis.hadm_id = da.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
  ON fis.subject_id = pt.subject_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 77 AND 87
  AND fis.stay_seq = 1;