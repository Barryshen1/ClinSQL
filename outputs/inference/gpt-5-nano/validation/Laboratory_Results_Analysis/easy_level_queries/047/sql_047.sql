WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON dd.icd_code = di.icd_code
   AND dd.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(dd.long_title) LIKE '%heart failure%'
    AND LOWER(p.gender) = 'm'
),
creatinine_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%creatinine%'
    AND LOWER(fluid) LIKE '%serum%'
),
max_creatinine_per_adm AS (
  SELECT
    ha.hadm_id,
    MAX(le.valuenum) AS max_creatinine_24h
  FROM hf_admissions AS ha
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.subject_id = ha.subject_id
   AND le.hadm_id = ha.hadm_id
  JOIN creatinine_items AS ci
    ON le.itemid = ci.itemid
  WHERE le.charttime >= ha.admittime
    AND le.charttime <= TIMESTAMP_ADD(ha.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
    AND LOWER(le.valueuom) LIKE '%mg/dl%'
  GROUP BY ha.hadm_id
)
SELECT
  MAX(max_creatinine_24h) AS max_serum_creatinine_mg_per_dl_within_24h
FROM max_creatinine_per_adm;