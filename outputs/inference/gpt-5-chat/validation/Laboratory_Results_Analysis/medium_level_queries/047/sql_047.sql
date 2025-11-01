WITH acs_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND (
      -- ICD-9 ACS patterns
      (d.icd_version = 9 AND (
        d.icd_code LIKE '410%' OR
        d.icd_code = '4111' OR
        d.icd_code IN ('41181','41189')
      ))
      -- ICD-10 ACS patterns
      OR (d.icd_version = 10 AND (
        d.icd_code LIKE 'I21%' OR
        d.icd_code LIKE 'I22%' OR
        d.icd_code = 'I200'
      ))
      -- As extra safety: text contains 'acute' and 'coronary' (optional)
    )
),
troponin_t_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
    AND LOWER(fluid) = 'blood'
),
initial_trop AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_itemids t
    ON l.itemid = t.itemid
  JOIN acs_patients ap
    ON l.hadm_id = ap.hadm_id
  WHERE l.valuenum IS NOT NULL
)
SELECT
  COUNT(DISTINCT i.subject_id) AS patient_count,
  COUNT(DISTINCT i.hadm_id) AS admission_count,
  AVG(i.valuenum) AS initial_troponin_mean,
  APPROX_QUANTILES(i.valuenum, 2)[OFFSET(1)] AS initial_troponin_median,
  APPROX_QUANTILES(i.valuenum, 4)[OFFSET(1)] AS troponin_q1,
  APPROX_QUANTILES(i.valuenum, 4)[OFFSET(3)] AS troponin_q3
FROM initial_trop i
WHERE i.rn = 1
  AND i.valuenum > 0.01;  -- 99th percentile cutoff;