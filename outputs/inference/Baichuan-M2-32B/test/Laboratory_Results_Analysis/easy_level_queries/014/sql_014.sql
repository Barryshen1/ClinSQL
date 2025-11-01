WITH qualifying_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age = 45
    AND d.icd_version = 10
    AND (dd.long_title LIKE '%bleeding%' OR dd.long_title LIKE '%hemorrhage%' OR dd.long_title LIKE '%hematemesis%' OR dd.long_title LIKE '%melena%')
),
discharge_day_hemoglobin AS (
  SELECT 
    qa.hadm_id,
    qa.dischtime,
    lb.valuenum AS hemoglobin,
    lb.charttime,
    ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY lb.charttime DESC) AS rn
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lb
    ON qa.subject_id = lb.subject_id AND qa.hadm_id = lb.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON lb.itemid = dli.itemid
  WHERE 
    DATE(lb.charttime) = DATE(qa.dischtime)
    AND dli.category = 'Hematology'
    AND dli.label LIKE '%hemoglobin%'
    AND lb.valueuom = 'g/dL'
    AND lb.valuenum IS NOT NULL
    AND lb.valuenum BETWEEN 5 AND 20
),
last_hemoglobin AS (
  SELECT 
    hadm_id,
    hemoglobin
  FROM discharge_day_hemoglobin
  WHERE rn = 1
)
SELECT 
  APPROX_QUANTILES(hemoglobin, 100)[OFFSET(75)] AS discharge_day_hemoglobin_p75
FROM last_hemoglobin;