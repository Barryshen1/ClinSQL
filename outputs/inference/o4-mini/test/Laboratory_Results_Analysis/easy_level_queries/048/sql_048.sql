WITH copd_admissions AS (
  -- Hospital admissions of female patients with a COPD diagnosis
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id
   AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND LOWER(di.long_title) LIKE '%copd%'
),
creatinine_items AS (
  -- Identify lab items corresponding to serum creatinine
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
),
avg_creatinine_per_admission AS (
  -- Compute the average creatinine in the first 24h for each COPD admission
  SELECT
    c.hadm_id,
    AVG(le.valuenum) AS avg_creat
  FROM copd_admissions c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.subject_id = le.subject_id
   AND c.hadm_id = le.hadm_id
  JOIN creatinine_items ci
    ON le.itemid = ci.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.admittime
                         AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
)
-- Compute the 75th percentile of the per‐admission averages
SELECT
  -- APPROX_QUANTILES returns an array of N+1 quantiles; offset 75 for the 75th percentile of 100 buckets
  APPROX_QUANTILES(avg_creat, 100)[OFFSET(75)] AS creatinine_75th_percentile
FROM avg_creatinine_per_admission;