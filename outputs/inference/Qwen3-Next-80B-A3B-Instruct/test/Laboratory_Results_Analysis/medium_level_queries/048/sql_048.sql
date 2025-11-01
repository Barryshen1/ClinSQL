WITH ami_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND LOWER(d_icd.long_title) LIKE '%acute myocardial infarction%'
),
first_hstnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems di ON l.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%hs%troponin%t%'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
)
SELECT 
  COUNT(DISTINCT fa.subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(fh.valuenum) AS mean_hstnt,
  PERCENTILE_CONT(fh.valuenum, 0.5) AS median_hstnt,
  PERCENTILE_CONT(fh.valuenum, 0.25) AS q1_hstnt,
  PERCENTILE_CONT(fh.valuenum, 0.75) AS q3_hstnt
FROM first_hstnt fh
JOIN ami_admissions fa ON fh.hadm_id = fa.hadm_id
WHERE fh.rn = 1
  AND fh.valuenum > 0.01;