WITH pneumonia_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE 
    pat.gender = 'M' AND
    d.long_title LIKE '%pneumonia%'
),
peak_creatinine_per_admission AS (
  SELECT 
    le.hadm_id, 
    MAX(le.valuenum) AS peak_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN pneumonia_admissions pa
    ON le.hadm_id = pa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  WHERE 
    le.itemid = 50912 AND  -- Serum Creatinine
    le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
)
SELECT 
  STDDEV_SAMP(peak_creatinine) AS std_dev_peak_creatinine
FROM peak_creatinine_per_admission;