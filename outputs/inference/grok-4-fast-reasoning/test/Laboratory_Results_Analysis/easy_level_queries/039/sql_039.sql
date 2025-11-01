WITH pneumonia_hadms AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON diag.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (
      (diag.icd_version = 9 
       AND SAFE_CAST(SUBSTR(diag.icd_code, 1, 3) AS INT64) BETWEEN 480 AND 486)
      OR (diag.icd_version = 10 
          AND (diag.icd_code LIKE 'J12%' OR diag.icd_code LIKE 'J13%' 
               OR diag.icd_code LIKE 'J14%' OR diag.icd_code LIKE 'J15%' 
               OR diag.icd_code LIKE 'J16%' OR diag.icd_code LIKE 'J17%' 
               OR diag.icd_code LIKE 'J18%'))
    )
)
SELECT STDDEV(peak_creatinine) AS stddev_peak_serum_creatinine
FROM (
  SELECT adm.hadm_id, MAX(lab.valuenum) AS peak_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
    ON adm.hadm_id = lab.hadm_id
  JOIN pneumonia_hadms ph 
    ON adm.hadm_id = ph.hadm_id
  WHERE lab.itemid = 50912
    AND lab.valuenum IS NOT NULL
    AND lab.charttime >= adm.admittime
    AND lab.charttime <= adm.dischtime
  GROUP BY adm.hadm_id
  HAVING peak_creatinine IS NOT NULL
);