WITH sepsis_admissions AS (
  SELECT DISTINCT adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE pat.gender = 'M'
    AND LOWER(d.long_title) LIKE '%sepsis%'
),
first_platelet AS (
  SELECT 
    le.hadm_id,
    le.valuenum AS platelet_count,
    ROW_NUMBER() OVER (
      PARTITION BY le.hadm_id 
      ORDER BY le.charttime
    ) AS rn
  FROM sepsis_admissions sa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  WHERE le.itemid = 51265  -- Platelet Count
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN sa.admittime AND DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
)
SELECT STDDEV(platelet_count) AS platelet_std_dev
FROM first_platelet
WHERE rn = 1;  -- First platelet count per admission;