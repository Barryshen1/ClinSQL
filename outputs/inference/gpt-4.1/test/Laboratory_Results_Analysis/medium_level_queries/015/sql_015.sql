WITH acs_icd_codes AS (
  -- ICD-10 codes for ACS: I20-I25
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
    AND (
      REGEXP_CONTAINS(icd_code, r'^I2[0-5]')
    )
),
acs_admissions AS (
  -- Admissions with ACS diagnosis
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acs_icd_codes c
    ON d.icd_code = c.icd_code AND d.icd_version = 10
),
female_patients AS (
  -- Female patients aged 88-98
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 88 AND 98
),
troponin_t_items AS (
  -- Troponin T itemids (lab tests)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin_t AS (
  -- First Troponin T value per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN troponin_t_items t ON l.itemid = t.itemid
  WHERE l.valuenum IS NOT NULL
    AND LOWER(l.valueuom) = 'ng/ml'
)
SELECT
  APPROX_QUANTILES(ft.valuenum, 4)[OFFSET(2)] AS median_troponin_t_ng_ml,
  APPROX_QUANTILES(ft.valuenum, 4)[OFFSET(1)] AS troponin_t_25th_percentile_ng_ml,
  APPROX_QUANTILES(ft.valuenum, 4)[OFFSET(3)] AS troponin_t_75th_percentile_ng_ml
FROM first_troponin_t ft
JOIN acs_admissions a
  ON ft.subject_id = a.subject_id AND ft.hadm_id = a.hadm_id
JOIN female_patients p
  ON ft.subject_id = p.subject_id
WHERE ft.rn = 1
  AND ft.valuenum > 0.01;