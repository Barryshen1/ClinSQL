WITH heart_failure_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND d.icd_code IN (
      '428.0', '428.1', '428.2', '428.20', '428.21', '428.22', '428.23', '428.3', '428.30', '428.31', '428.32', '428.33', '428.4', '428.40', '428.41', '428.42', '428.43', '428.9',
      'I50.0', 'I50.1', 'I50.2', 'I50.20', 'I50.21', 'I50.22', 'I50.23', 'I50.3', 'I50.30', 'I50.31', 'I50.32', 'I50.33', 'I50.4', 'I50.40', 'I50.41', 'I50.42', 'I50.43', 'I50.9'
    )
),
hemoglobin_nadir AS (
  SELECT
    hfa.hadm_id,
    MIN(l.valuenum) AS nadir_hb
  FROM heart_failure_admissions hfa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON hfa.hadm_id = l.hadm_id
    AND l.charttime BETWEEN hfa.admittime AND hfa.dischtime
  WHERE l.itemid = 50811  -- Hemoglobin lab code
    AND l.valuenum IS NOT NULL
  GROUP BY hfa.hadm_id
)
SELECT
  APPROX_QUANTILES(nadir_hb, 100)[OFFSET(75)] AS hb_75th_percentile
FROM hemoglobin_nadir;