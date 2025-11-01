WITH hf_adm AS (
  SELECT 
    subject_id, 
    hadm_id, 
    MIN(CASE WHEN is_hf = 1 THEN seq_num END) AS min_seq_hf
  FROM (
    SELECT 
      subject_id, 
      hadm_id, 
      seq_num, 
      CASE 
        WHEN (icd_version = 9 AND icd_code LIKE '428%') 
          OR (icd_version = 10 AND icd_code LIKE 'I50%') 
        THEN 1 
        ELSE 0 
      END AS is_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  )
  GROUP BY subject_id, hadm_id
  HAVING min_seq_hf IS NOT NULL  -- At least one HF diagnosis
),
cohort_adm AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender, 
    p.anchor_age,
    h.min_seq_hf,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN hf_adm h 
    ON a.subject_id = h.subject_id AND a.hadm_id = h.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 67 AND 77
),
imaging_counts AS (
  SELECT 
    ca.subject_id, 
    ca.hadm_id,
    COUNT(CASE 
      WHEN (pi.icd_version = 9 AND (pi.icd_code LIKE '87%' OR pi.icd_code LIKE '88%' OR pi.icd_code LIKE '89%'))
        OR (pi.icd_version = 10 AND pi.icd_code LIKE 'B%')
      THEN 1 
    END) AS num_imaging
  FROM cohort_adm ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ca.subject_id = pi.subject_id AND ca.hadm_id = pi.hadm_id
  GROUP BY ca.subject_id, ca.hadm_id
),
stratified_data AS (
  SELECT 
    CASE WHEN ca.min_seq_hf = 1 THEN 'Primary' ELSE 'Secondary' END AS hf_type,
    CASE 
      WHEN ca.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN ca.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    COALESCE(ic.num_imaging, 0) AS num_imaging
  FROM cohort_adm ca
  INNER JOIN imaging_counts ic 
    ON ca.subject_id = ic.subject_id AND ca.hadm_id = ic.hadm_id
  WHERE ca.los_days BETWEEN 1 AND 7
)
SELECT 
  hf_type,
  los_group,
  APPROX_QUANTILES(num_imaging, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_imaging, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_imaging, 4)[OFFSET(3)] AS p75
FROM stratified_data
GROUP BY hf_type, los_group
ORDER BY hf_type, los_group;