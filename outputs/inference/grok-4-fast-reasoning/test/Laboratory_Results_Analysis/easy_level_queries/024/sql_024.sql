WITH sepsis_hadms AS (
  SELECT DISTINCT diag.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON diag.icd_code = d_icd.icd_code
    AND diag.icd_version = d_icd.icd_version
  WHERE LOWER(d_icd.long_title) LIKE '%sepsis%'
     OR LOWER(d_icd.long_title) LIKE '%septic%'
),
platelet_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%count%'
),
admission_platelets AS (
  SELECT 
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.subject_id = le.subject_id
    AND adm.hadm_id = le.hadm_id
    AND le.charttime >= adm.admittime
  JOIN platelet_items pi
    ON le.itemid = pi.itemid
  WHERE le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT STDDEV(plat.valuenum) AS sd_platelet_count
FROM admission_platelets plat
JOIN sepsis_hadms sh
  ON plat.hadm_id = sh.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON plat.subject_id = pat.subject_id
WHERE pat.gender = 'M';