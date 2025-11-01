WITH acs_admissions AS (
  -- Identify ACS admissions (ICD-9: 410.*, 411.1; ICD-10: I21.*, I20.0)
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE 
    (d.icd_version = 9 AND (
      REGEXP_CONTAINS(d.icd_code, r'^410') OR d.icd_code = '4111'
    ))
    OR
    (d.icd_version = 10 AND (
      REGEXP_CONTAINS(d.icd_code, r'^I21') OR d.icd_code = 'I200'
    ))
),
female_acs_admissions AS (
  -- Restrict to female patients
  SELECT a.subject_id, a.hadm_id
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
),
troponin_items AS (
  -- Get itemids for troponin from d_labitems
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
),
nadir_troponin_per_admission AS (
  -- For each admission, get the nadir troponin value
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN female_acs_admissions fa
    ON l.subject_id = fa.subject_id AND l.hadm_id = fa.hadm_id
  INNER JOIN troponin_items ti
    ON l.itemid = ti.itemid
  WHERE l.valuenum IS NOT NULL
  GROUP BY l.subject_id, l.hadm_id
)
-- Compute the 25th percentile of nadir troponin values
SELECT
  APPROX_QUANTILES(nadir_troponin, 4)[OFFSET(1)] AS troponin_nadir_25th_percentile
FROM nadir_troponin_per_admission;