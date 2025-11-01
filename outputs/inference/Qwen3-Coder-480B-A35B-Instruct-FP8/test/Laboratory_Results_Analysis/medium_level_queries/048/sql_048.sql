WITH ami_admissions AS (
  -- Identify admissions with AMI diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE (
    (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
    (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
  )
),

eligible_patients AS (
  -- Filter female patients aged 55–65
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 55 AND 65
),

first_hstnt AS (
  -- Get first hs-TnT lab value > 0.01 ng/mL for each admission
  SELECT
    l.hadm_id,
    l.valuenum AS first_hstnt_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
),

first_hstnt_filtered AS (
  -- Keep only the first measurement per admission
  SELECT hadm_id, first_hstnt_value
  FROM first_hstnt
  WHERE rn = 1
)

-- Final aggregation
SELECT
  COUNT(DISTINCT a.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(f.first_hstnt_value) AS mean_hstnt,
  APPROX_QUANTILES(f.first_hstnt_value, 2)[OFFSET(1)] AS median_hstnt,
  APPROX_QUANTILES(f.first_hstnt_value, 4)[OFFSET(1)] AS q1_hstnt,
  APPROX_QUANTILES(f.first_hstnt_value, 4)[OFFSET(3)] AS q3_hstnt,
  APPROX_QUANTILES(f.first_hstnt_value, 4)[OFFSET(3)] - APPROX_QUANTILES(f.first_hstnt_value, 4)[OFFSET(1)] AS iqr_hstnt
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN eligible_patients ep ON a.subject_id = ep.subject_id
JOIN ami_admissions aa ON a.hadm_id = aa.hadm_id
JOIN first_hstnt_filtered f ON a.hadm_id = f.hadm_id;