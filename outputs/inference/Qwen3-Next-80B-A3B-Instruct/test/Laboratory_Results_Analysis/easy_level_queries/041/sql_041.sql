WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, p.anchor_age, p.gender
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(di.long_title) LIKE '%pneumonia%'
),
creatinine_labs AS (
  SELECT l.hadm_id, l.charttime, l.valuenum
  FROM physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl ON l.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%creatinine%'
    AND dl.fluid = 'Blood'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
),
creatinine_first_24h AS (
  SELECT c.hadm_id, AVG(c.valuenum) AS avg_creatinine_24h
  FROM creatinine_labs c
  JOIN pneumonia_admissions pa ON c.hadm_id = pa.hadm_id
  WHERE c.charttime >= pa.admittime
    AND c.charttime < pa.admittime + INTERVAL 24 HOUR
  GROUP BY c.hadm_id
)
SELECT STDDEV(avg_creatinine_24h) AS sd_avg_creatinine_24h
FROM creatinine_first_24h;