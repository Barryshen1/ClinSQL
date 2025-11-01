WITH acs_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE (di.long_title LIKE '%acute coronary syndrome%' OR di.long_title LIKE '%myocardial infarction%' OR di.long_title LIKE '%unstable angina%')
    OR (d.icd_version = 10 AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    OR (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code = '411.1'))
),

female_67_77 AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
),

troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE LOWER(di.label) LIKE '%troponin t%'
    AND l.charttime >= a.admittime
)

SELECT
  COUNT(*) AS admission_count,
  AVG(t.valuenum) AS mean_troponin,
  PERCENTILE_CONT(t.valuenum, 0.5) AS median_troponin,
  PERCENTILE_CONT(t.valuenum, 0.75) - PERCENTILE_CONT(t.valuenum, 0.25) AS iqr_troponin
FROM female_67_77 f
JOIN acs_admissions a ON f.hadm_id = a.hadm_id
JOIN troponin_first t ON f.hadm_id = t.hadm_id
WHERE t.rn = 1
  AND t.valuenum > CAST(t.ref_range_upper AS FLOAT64)
  AND t.ref_range_upper IS NOT NULL;