WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 69 AND 79
    AND adm.hadm_id IN (
      -- Admissions with UGIB
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        -- ICD-9 codes
        (icd_version = 9 AND (
          icd_code IN ('4560','45620','5307','53021','53082','53100','53101','53120','53121','53140','53141','53160','53161','53200','53201','53220','53221','53240','53241','53260','53261','53300','53301','53320','53321','53340','53341','53360','53361','53400','53401','53420','53421','53440','53441','53460','53461','53501','53511','53521','53531','53541','53551','53561','53783','56985','5780','5781','5789')
          OR SUBSTR(icd_code, 1, 3) IN ('530','531','532','533','534','535')
        ))
        OR 
        -- ICD-10 codes
        (icd_version = 10 AND (
          icd_code IN ('K22.1','K22.6','K25.0','K25.2','K25.4','K25.6','K26.0','K26.2','K26.4','K26.6','K27.0','K27.2','K27.4','K27.6','K28.0','K28.2','K28.4','K28.6','K92.0','K92.1','K92.2')
          OR SUBSTR(icd_code, 1, 3) IN ('K25','K26','K27','K28')
        ))
    )
    AND adm.hadm_id IN (
      -- Admissions with COPD exacerbation
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code IN ('49121','49122','49321','49322'))
        OR (icd_version = 10 AND icd_code IN ('J44.0','J44.1'))
    )
)
SELECT 
  ROUND(APPROX_QUANTILES(los_days, 2)[OFFSET(1)], 2) AS median_los
FROM cohort;