WITH sepsis_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 18
    AND p.anchor_age <= 89
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'A41%'
),
platelet_labs AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN sepsis_admissions sa
    ON le.hadm_id = sa.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE li.label = 'Platelet count'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= DATETIME(sa.admittime)
    AND le.charttime <= TIMESTAMP_ADD(DATETIME(sa.admittime), INTERVAL 1 DAY)
),
first_platelet AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum
  FROM (
    SELECT 
      subject_id,
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM platelet_labs
  )
  WHERE rn = 1
)
SELECT 
  STDDEV(valuenum) AS platelet_stddev
FROM first_platelet;