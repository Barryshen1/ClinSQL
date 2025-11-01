WITH acs_codes AS (
  SELECT '410%' AS pattern, 9 AS icd_version UNION ALL -- ICD-9 AMI
  SELECT '411%' , 9 UNION ALL -- ICD-9 acute coronary insufficiency
  SELECT 'I20.0', 10 UNION ALL -- ICD-10 unstable angina
  SELECT 'I21%' , 10 UNION ALL -- ICD-10 AMI
  SELECT 'I22%' , 10           -- ICD-10 subsequent AMI
),
acs_admissions AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    CASE WHEN MIN(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1
         THEN 'primary' ELSE 'secondary' END AS acs_dx_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN acs_codes ac
    ON di.icd_version = ac.icd_version
   AND di.icd_code LIKE ac.pattern
  GROUP BY di.subject_id, di.hadm_id
),
diagnostic_proc_counts AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    COUNT(*) AS diagnostic_proc_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dpi
    ON pi.icd_code = dpi.icd_code
   AND pi.icd_version = dpi.icd_version
  WHERE LOWER(dpi.long_title) LIKE '%diagnostic%'
  GROUP BY pi.subject_id, pi.hadm_id
),
base_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
),
cohort AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    acs.acs_dx_type,
    CASE WHEN b.los_days BETWEEN 1 AND 3 THEN '1-3d'
         WHEN b.los_days BETWEEN 4 AND 7 THEN '4-7d'
         ELSE NULL END AS los_group,
    COALESCE(dpc.diagnostic_proc_count, 0) AS diagnostic_proc_count
  FROM base_cohort b
  JOIN acs_admissions acs
    ON b.subject_id = acs.subject_id
   AND b.hadm_id = acs.hadm_id
  LEFT JOIN diagnostic_proc_counts dpc
    ON b.subject_id = dpc.subject_id
   AND b.hadm_id = dpc.hadm_id
  WHERE b.los_days BETWEEN 1 AND 7
)
SELECT
  los_group,
  acs_dx_type,
  COUNT(DISTINCT hadm_id) AS n_admissions,
  quantiles[OFFSET(1)] AS p25,
  quantiles[OFFSET(2)] AS p50,
  quantiles[OFFSET(3)] AS p75
FROM (
  SELECT
    los_group,
    acs_dx_type,
    APPROX_QUANTILES(diagnostic_proc_count, 4) AS quantiles,
    ARRAY_AGG(DISTINCT hadm_id) AS hadm_ids
  FROM cohort
  WHERE los_group IS NOT NULL
  GROUP BY los_group, acs_dx_type
)
ORDER BY los_group, acs_dx_type;