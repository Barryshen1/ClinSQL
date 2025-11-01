WITH qualifying_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) = 65
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        )
    )
)
SELECT 
  MIN(lab.valuenum) AS min_sodium
FROM 
  `physionet-data.mimiciv_3_1_hosp.labevents` lab
INNER JOIN 
  qualifying_admissions qa
  ON lab.hadm_id = qa.hadm_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
  ON lab.itemid = dlab.itemid
WHERE 
  dlab.label = 'SODIUM' 
  AND dlab.fluid = 'Blood'
  AND lab.valuenum IS NOT NULL
  AND lab.charttime >= qa.admittime - INTERVAL '24' HOUR
  AND lab.charttime <= qa.admittime + INTERVAL '24' HOUR;