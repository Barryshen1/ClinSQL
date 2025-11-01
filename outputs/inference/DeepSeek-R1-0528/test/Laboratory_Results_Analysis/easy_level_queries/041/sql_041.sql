WITH serum_creat_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%' 
    AND LOWER(fluid) = 'blood'
), cohort AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 45 AND 55
    AND LOWER(d.long_title) LIKE '%pneumonia%'
), first_24h_creat AS (
  SELECT
    c.hadm_id,
    lab.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON c.hadm_id = lab.hadm_id
    AND c.subject_id = lab.subject_id
  WHERE
    lab.itemid IN (SELECT itemid FROM serum_creat_itemids)
    AND lab.valuenum IS NOT NULL
    AND lab.valueuom = 'mg/dL'
    AND lab.charttime >= c.admittime
    AND lab.charttime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
), avg_creat_per_admission AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM first_24h_creat
  GROUP BY hadm_id
)
SELECT STDDEV(avg_creatinine) AS sd_avg_creatinine
FROM avg_creat_per_admission;