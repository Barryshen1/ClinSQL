WITH eligible_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, SECOND) / 86400.0 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 75 AND 85
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag1
      WHERE 
        diag1.subject_id = adm.subject_id 
        AND diag1.hadm_id = adm.hadm_id
        AND (
          (diag1.icd_version = 9 AND SUBSTR(diag1.icd_code, 1, 3) IN ('410','411','412','413','414'))
          OR 
          (diag1.icd_version = 10 AND SUBSTR(diag1.icd_code, 1, 3) IN ('I20','I21','I22','I23','I24','I25'))
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag2
      WHERE 
        diag2.subject_id = adm.subject_id 
        AND diag2.hadm_id = adm.hadm_id
        AND (
          (diag2.icd_version = 9 AND SUBSTR(diag2.icd_code, 1, 3) IN ('491','492','496'))
          OR 
          (diag2.icd_version = 10 AND SUBSTR(diag2.icd_code, 1, 3) IN ('J41','J42','J43','J44'))
        )
    )
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS percentile_75_los_days
FROM eligible_admissions;