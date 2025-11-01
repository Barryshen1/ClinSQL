WITH sepsis_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%sepsis%'
  GROUP BY di.hadm_id
),
male_83 AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age = 83
),
creatinine_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) = 'creatinine' AND LOWER(fluid) = 'blood'
),
admission_creat AS (
  SELECT
    a.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY a.hadm_id
      ORDER BY ABS(TIMESTAMP_DIFF(le.charttime, a.admittime, MINUTE))
    ) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_83 m ON a.subject_id = m.subject_id
  JOIN sepsis_admissions s ON a.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
  CROSS JOIN creatinine_item ci
  WHERE le.itemid = ci.itemid
    AND le.charttime >= a.admittime - INTERVAL 24 HOUR
    AND le.charttime <= a.admittime + INTERVAL 24 HOUR
    AND le.valuenum IS NOT NULL
)
SELECT MAX(valuenum) AS max_admission_creatinine
FROM admission_creat
WHERE rn = 1;