WITH tnt_item AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems 
  WHERE label LIKE '%TROPONIN-T%'
),
le_first AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.valuenum, 
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON le.subject_id = a.subject_id 
    AND le.hadm_id = a.hadm_id
  WHERE le.itemid IN (SELECT itemid FROM tnt_item)
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT
  COUNT(DISTINCT p.subject_id) AS patient_count,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(le.valuenum) AS mean_hs_tnt,
  APPROX_QUANTILES(le.valuenum, 100)[OFFSET(50)] AS median_hs_tnt,
  APPROX_QUANTILES(le.valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(le.valuenum, 100)[OFFSET(25)] AS iqr_hs_tnt
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON a.subject_id = diag.subject_id 
  AND a.hadm_id = diag.hadm_id 
  AND diag.seq_num = 1
INNER JOIN le_first le
  ON a.subject_id = le.subject_id 
  AND a.hadm_id = le.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 55 AND 65
  AND le.valuenum > 0.01
  AND (
    (diag.icd_version = 9 AND diag.icd_code LIKE '410%') 
    OR 
    (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
  );