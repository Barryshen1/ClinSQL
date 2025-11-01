WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%Acute Coronary Syndrome%'
     OR di.icd_code LIKE 'I20.0%'
     OR di.icd_code LIKE 'I21%'
     OR di.icd_code LIKE 'I22%'
     OR di.icd_code LIKE 'I24.8%'
     OR di.icd_code LIKE 'I24.9%'
),
troponin_first AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0.01
),
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
    AND a.hadm_id IN (SELECT hadm_id FROM acs_admissions)
),
first_troponin_filtered AS (
  SELECT tf.valuenum
  FROM troponin_first tf
  JOIN filtered_patients fp ON tf.hadm_id = fp.hadm_id
  WHERE tf.rn = 1
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_troponin_t,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_troponin_t
FROM first_troponin_filtered;