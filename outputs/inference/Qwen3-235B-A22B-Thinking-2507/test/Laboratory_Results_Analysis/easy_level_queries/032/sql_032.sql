WITH copd_admissions AS (
  SELECT 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) = 90
    AND (
        (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
        OR (d.icd_version = 9 AND d.icd_code = '496')
    )
  GROUP BY a.hadm_id
),
creatinine_measurements AS (
  SELECT 
    ca.hadm_id,
    le.valuenum
  FROM copd_admissions ca
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ca.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'CREATININE'
    AND dli.fluid = 'Blood'
    AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
    AND le.valuenum IS NOT NULL
),
avg_creatinine_per_admission AS (
  SELECT 
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM creatinine_measurements
  GROUP BY hadm_id
)
SELECT 
  STDDEV_POP(avg_creatinine) AS std_dev_avg_creatinine
FROM avg_creatinine_per_admission;