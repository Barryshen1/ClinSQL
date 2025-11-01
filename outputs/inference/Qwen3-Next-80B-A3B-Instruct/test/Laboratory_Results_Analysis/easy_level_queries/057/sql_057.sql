WITH pneumonia_admissions AS (
  SELECT DISTINCT p.subject_id, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age = 61
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),
nadir_creatinine AS (
  SELECT pa.hadm_id, MIN(le.valuenum) AS nadir_creatinine
  FROM pneumonia_admissions pa
  JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON pa.hadm_id = le.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
  GROUP BY pa.hadm_id
)
SELECT 
  PERCENTILE_CONT(nadir_creatinine, 0.75) - PERCENTILE_CONT(nadir_creatinine, 0.25) AS iqr_nadir_creatinine
FROM nadir_creatinine;