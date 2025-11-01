WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id AND di.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
    AND p.gender = 'M'
),
creatinine_peaks AS (
  SELECT pa.hadm_id,
         MAX(le.valuenum) AS peak_creatinine
  FROM pneumonia_admissions AS pa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = pa.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON di.itemid = le.itemid
  WHERE LOWER(di.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
  GROUP BY pa.hadm_id
)
SELECT STDDEV_SAMP(peak_creatinine) AS sd_peak_creatinine
FROM creatinine_peaks;