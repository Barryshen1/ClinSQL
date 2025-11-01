WITH qualifying_admissions AS (
  SELECT 
    adm.hadm_id,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) = 87
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' OR diag.icd_code LIKE 'I61%' OR diag.icd_code LIKE 'I62%'))
          OR (diag.icd_version = 9 AND (diag.icd_code LIKE '430%' OR diag.icd_code LIKE '431%' OR diag.icd_code LIKE '432%'))
        )
    )
),
discharge_day_platelets AS (
  SELECT 
    lab.valuenum AS platelet_count
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON qa.hadm_id = lab.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON lab.itemid = dlab.itemid
  WHERE 
    dlab.label = 'Platelets'
    AND DATE(lab.charttime) = DATE(qa.dischtime)
    AND lab.valuenum IS NOT NULL
)
SELECT 
  ANY_VALUE(p75) AS p75_platelet_count
FROM (
  SELECT 
    PERCENTILE_CONT(platelet_count, 0.75) OVER () AS p75
  FROM discharge_day_platelets
);