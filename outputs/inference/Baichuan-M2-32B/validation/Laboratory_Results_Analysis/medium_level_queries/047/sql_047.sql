WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
eligible_patients AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    age_at_admission
  FROM patient_admissions
  WHERE age_at_admission BETWEEN 67 AND 77
),
acs_admissions AS (
  SELECT DISTINCT
    e.subject_id,
    e.hadm_id,
    e.admittime,  -- Added missing columns
    e.dischtime   -- Added missing columns
  FROM eligible_patients e
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON e.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE d.icd_version = 10
    AND dd.icd_code IN (
      'I20.0', 'I20.1', 'I20.8', 'I20.9',
      'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',
      'I22.0', 'I22.1', 'I22.2', 'I22.3', 'I22.4', 'I22.5', 'I22.6', 'I22.7', 'I22.8', 'I22.9',
      'I24.0', 'I24.1', 'I24.2', 'I24.3', 'I24.4', 'I24.5', 'I24.6', 'I24.7', 'I24.8', 'I24.9'
    )
),
troponin_t AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_upper
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%trop t%' OR LOWER(dl.label) LIKE '%troponin t%'
    AND l.valuenum IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),
first_troponin AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.valuenum AS initial_troponin,
    t.ref_range_upper
  FROM troponin_t t
  INNER JOIN acs_admissions a
    ON t.hadm_id = a.hadm_id
  WHERE t.charttime BETWEEN a.admittime AND a.dischtime
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY t.hadm_id
    ORDER BY t.charttime
  ) = 1
),
eligible_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    initial_troponin
  FROM first_troponin
  WHERE initial_troponin > ref_range_upper
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  AVG(initial_troponin) AS mean_troponin,
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(50)] AS median_troponin,
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(initial_troponin, 100)[OFFSET(75)] AS q3,
  (APPROX_QUANTILES(initial_troponin, 100)[OFFSET(75)] - APPROX_QUANTILES(initial_troponin, 100)[OFFSET(25)]) AS iqr
FROM eligible_admissions;