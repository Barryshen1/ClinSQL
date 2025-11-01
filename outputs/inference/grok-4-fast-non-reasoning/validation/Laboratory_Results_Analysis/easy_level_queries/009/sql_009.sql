WITH troponin_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin%'
    AND category = 'Chemistry'
),
acs_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND d.icd_version = '10'
    AND (d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I21%')
),
nadir_troponin AS (
  SELECT 
    aa.hadm_id,
    MIN(le.valuenum) AS nadir_troponin
  FROM acs_admissions aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON aa.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.subject_id = le.subject_id
    AND aa.hadm_id = le.hadm_id
    AND le.itemid IN (SELECT itemid FROM troponin_itemids)
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY aa.hadm_id
  HAVING nadir_troponin IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.25) OVER() AS p25_nadir_troponin
FROM nadir_troponin;