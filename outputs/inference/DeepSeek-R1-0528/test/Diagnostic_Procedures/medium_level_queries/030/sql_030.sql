WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND adm.hadm_id IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code IN ('530.7', '530.21', '531.00', '531.01', '531.20', '531.21', '532.00', '532.01', '532.20', '532.21', '533.00', '533.01', '533.20', '533.21', '534.00', '534.01', '534.20', '534.21'))
        OR 
        (icd_version = 10 AND icd_code IN ('K22.6', 'K25.0', 'K25.4', 'K26.0', 'K26.4', 'K27.0', 'K27.4', 'K28.0', 'K28.4', 'K92.2', 'I85.01', 'I85.11'))
    )
),
filtered_admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    los_days
  FROM base_admissions
  WHERE 
    age_at_admission BETWEEN 53 AND 63
    AND los_days BETWEEN 1 AND 8
),
admission_procedures AS (
  SELECT 
    fa.subject_id,
    fa.hadm_id,
    fa.los_days,
    COUNT(CASE WHEN LOWER(dip.long_title) LIKE '%diagnostic%' THEN proc.icd_code END) AS num_diagnostic_procedures
  FROM filtered_admissions fa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON fa.hadm_id = proc.hadm_id AND fa.subject_id = proc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON proc.icd_code = dip.icd_code AND proc.icd_version = dip.icd_version
  GROUP BY fa.subject_id, fa.hadm_id, fa.los_days
)
SELECT 
  CASE 
    WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days' 
    WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days' 
  END AS los_group,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(3)] AS p75
FROM admission_procedures
GROUP BY los_group;