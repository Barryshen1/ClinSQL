WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') 
      OR 
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
troponin_events AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    LOWER(dli.label) LIKE '%troponin t%'
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id,
    valuenum AS first_troponin
  FROM (
    SELECT 
      hadm_id,
      valuenum,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
    FROM troponin_events
  ) ranked
  WHERE rn = 1
)
SELECT 
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  AVG(c.anchor_age) AS mean_age,
  AVG(DATETIME_DIFF(c.dischtime, c.admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(ft.first_troponin) AS mean_first_troponin,
  MIN(ft.first_troponin) AS min_first_troponin,
  MAX(ft.first_troponin) AS max_first_troponin,
  COUNTIF(c.hospital_expire_flag = 1) AS mortality_count,
  COUNTIF(c.hospital_expire_flag = 1) * 1.0 / COUNT(*) AS mortality_rate
FROM cohort c
INNER JOIN first_troponin ft
  ON c.hadm_id = ft.hadm_id
WHERE ft.first_troponin > 0.01;