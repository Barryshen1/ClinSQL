WITH acs_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 73 AND 83
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')  -- ICD-9 AMI
      OR (diag.icd_version = 9 AND diag.icd_code IN ('411.1', '411.81'))  -- ICD-9 ACS
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I20.0%')  -- Unstable angina
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')  -- STEMI
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')  -- Subsequent MI
    )
),
troponin_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.flag
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE
    dlab.label LIKE '%Troponin T%'  -- All Troponin T variants
    AND le.hadm_id IN (SELECT hadm_id FROM acs_admissions)  -- Optimize performance
),
cohort_with_troponin AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    t.flag AS first_troponin_flag
  FROM acs_admissions a
  LEFT JOIN troponin_events t
    ON a.hadm_id = t.hadm_id
    AND a.subject_id = t.subject_id
  QUALIFY ROW_NUMBER() OVER (  -- Get first Troponin T per admission
    PARTITION BY a.hadm_id
    ORDER BY t.charttime
  ) = 1
)
SELECT
  COUNT(*) AS total_admissions,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent
FROM cohort_with_troponin
WHERE first_troponin_flag IN ('High', 'H');  -- Elevated first Troponin T;