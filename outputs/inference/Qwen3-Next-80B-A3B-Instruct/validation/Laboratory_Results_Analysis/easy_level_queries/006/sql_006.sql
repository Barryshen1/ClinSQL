WITH copd_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, d.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON p.subject_id = d.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 50
    AND LOWER(dicd.long_title) LIKE '%copd%'
),
sodium_nadir AS (
  SELECT 
    cp.hadm_id,
    MIN(le.valuenum) AS nadir_sodium
  FROM copd_patients cp
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON cp.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'Sodium'
    AND le.valuenum IS NOT NULL
    AND le.valuenum BETWEEN 110 AND 180  -- Physiologically plausible range
  GROUP BY cp.hadm_id
)
SELECT 
  STDDEV(nadir_sodium) AS std_dev_nadir_sodium
FROM sodium_nadir
WHERE nadir_sodium IS NOT NULL;