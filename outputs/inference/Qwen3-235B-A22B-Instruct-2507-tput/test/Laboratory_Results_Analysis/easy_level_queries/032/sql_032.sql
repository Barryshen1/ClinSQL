WITH patient_copd AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age >= 90
    AND LOWER(d.long_title) LIKE '%chronic obstructive pulmonary disease%'
),
creatinine_lab AS (
  SELECT di.itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems di
  WHERE LOWER(di.label) = 'creatinine'
    AND LOWER(di.fluid) = 'blood'
),
admission_creatinine AS (
  SELECT
    le.hadm_id,
    AVG(le.valuenum) AS avg_creatinine_24h
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON le.hadm_id = a.hadm_id
  CROSS JOIN creatinine_lab cl
  WHERE le.itemid = cl.itemid
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY le.hadm_id
),
patient_admission AS (
  SELECT DISTINCT pc.subject_id, ac.hadm_id, ac.avg_creatinine_24h
  FROM patient_copd pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON pc.subject_id = a.subject_id
  INNER JOIN admission_creatinine ac ON a.hadm_id = ac.hadm_id
)
SELECT
  STDDEV(pa.avg_creatinine_24h) AS std_dev_avg_creatinine_first_24h
FROM patient_admission pa;