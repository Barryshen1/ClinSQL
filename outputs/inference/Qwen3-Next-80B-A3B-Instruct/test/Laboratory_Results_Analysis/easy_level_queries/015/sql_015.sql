WITH pneumonia_female_admissions AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND LOWER(d_icd.long_title) LIKE '%pneumonia%'
),
creatinine_measurements AS (
  SELECT 
    pfa.subject_id,
    pfa.hadm_id,
    le.charttime,
    le.valuenum
  FROM pneumonia_female_admissions pfa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON pfa.subject_id = le.subject_id AND pfa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= pfa.admittime
    AND le.charttime <= pfa.dischtime
),
moving_24h_avg AS (
  SELECT 
    subject_id,
    hadm_id,
    charttime,
    valuenum,
    AVG(valuenum) OVER (
      PARTITION BY subject_id, hadm_id 
      ORDER BY charttime 
      RANGE BETWEEN INTERVAL '24 HOUR' PRECEDING AND CURRENT ROW
    ) AS avg_creatinine_24h
  FROM creatinine_measurements
)
SELECT MIN(avg_creatinine_24h) AS min_24h_avg_serum_creatinine
FROM moving_24h_avg;