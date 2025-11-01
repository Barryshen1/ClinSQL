WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 59 AND 69
),
acs_diagnoses AS (
  SELECT di.subject_id, di.hadm_id, di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN patients_filtered pf ON di.subject_id = pf.subject_id
  WHERE (
    (di.icd_version = 9 AND (di.icd_code LIKE '410.%' OR di.icd_code = '411.1'))
    OR
    (di.icd_version = 10 AND (di.icd_code = 'I20.0' OR di.icd_code LIKE 'I21.%' OR di.icd_code LIKE 'I22.%'))
  )
),
acs_hadms AS (
  SELECT hadm_id, MIN(seq_num) AS min_acs_seq
  FROM acs_diagnoses
  GROUP BY hadm_id
),
admissions_acs AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    CASE WHEN ah.min_acs_seq = 1 THEN 'primary' ELSE 'secondary' END AS dx_group,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN acs_hadms ah ON a.hadm_id = ah.hadm_id
  WHERE a.hadm_id IS NOT NULL
),
los_grouped AS (
  SELECT 
    hadm_id,
    dx_group,
    CASE 
      WHEN los_days >= 1 AND los_days <= 3 THEN '1-3 days'
      WHEN los_days >= 4 AND los_days <= 7 THEN '4-7 days'
    END AS los_group
  FROM admissions_acs
  WHERE los_days >= 1 AND los_days <= 7
),
proc_counts AS (
  SELECT 
    lg.hadm_id,
    lg.los_group,
    lg.dx_group,
    COUNT(CASE 
      WHEN (
        -- Diagnostic procedures for ACS (e.g., cardiac cath, imaging, echo)
        (pi.icd_version = 9 AND (
          pi.icd_code LIKE '37.2%' OR  -- Cardiac cath
          pi.icd_code LIKE '88.%' OR   -- Diagnostic ultrasound/radiology
          pi.icd_code = '89.41' OR     -- Stress test
          pi.icd_code LIKE '00.24'     -- Coronary arteriography
        ))
        OR
        (pi.icd_version = 10 AND (
          pi.icd_code LIKE '4A02%' OR  -- Echo
          pi.icd_code LIKE 'B20%' OR   -- Angiocardiography
          pi.icd_code LIKE 'IC%'       -- Imaging procedures
        ))
      ) THEN pi.icd_code 
    END) AS proc_count
  FROM los_grouped lg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON lg.hadm_id = pi.hadm_id
  GROUP BY lg.hadm_id, lg.los_group, lg.dx_group
)
SELECT 
  los_group,
  dx_group,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(proc_count, 4)[OFFSET(3)] AS p75
FROM proc_counts
WHERE los_group IS NOT NULL
GROUP BY los_group, dx_group
ORDER BY los_group, dx_group;