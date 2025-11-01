WITH target_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id AND a.subject_id = diag.subject_id
  WHERE 
    p.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND (
      -- ICD-9 codes
      (diag.icd_version = 9 AND 
        (diag.icd_code IN ('5780','5781','5789','5307','53082','53501','53511','53521','53531','53541','53551','53561','53783') OR 
         diag.icd_code LIKE '5310%' OR diag.icd_code LIKE '5312%' OR diag.icd_code LIKE '5314%' OR diag.icd_code LIKE '5316%' OR
         diag.icd_code LIKE '5320%' OR diag.icd_code LIKE '5322%' OR diag.icd_code LIKE '5324%' OR diag.icd_code LIKE '5326%' OR
         diag.icd_code LIKE '5330%' OR diag.icd_code LIKE '5332%' OR diag.icd_code LIKE '5334%' OR diag.icd_code LIKE '5336%' OR
         diag.icd_code LIKE '5340%' OR diag.icd_code LIKE '5342%' OR diag.icd_code LIKE '5344%' OR diag.icd_code LIKE '5346%'
        )
      ) OR
      -- ICD-10 codes
      (diag.icd_version = 10 AND 
        diag.icd_code IN ('K920','K921','K922','K250','K252','K254','K256','K260','K262','K264','K266','K270','K272','K274','K276','K280','K282','K284','K286','K226','K228','I8501','I8511')
      )
    )
    -- Age at admission: 84–94 years
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
)
SELECT 
  approx_quantiles.los_q[OFFSET(25)] AS q25,
  approx_quantiles.los_q[OFFSET(75)] AS q75,
  approx_quantiles.los_q[OFFSET(75)] - approx_quantiles.los_q[OFFSET(25)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(los_days, 100) AS los_q
  FROM target_admissions
) approx_quantiles;