WITH copd_female_patients AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND LOWER(d_icd.long_title) LIKE '%copd%'
),
creatinine_in_first_24h AS (
  SELECT 
    cfp.hadm_id,
    le.valuenum AS creatinine_value
  FROM copd_female_patients cfp
  INNER JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON cfp.hadm_id = le.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'
    AND le.charttime >= cfp.admittime
    AND le.charttime < cfp.admittime + INTERVAL '24' HOUR
    AND le.valuenum IS NOT NULL
),
avg_creatinine_per_admission AS (
  SELECT 
    hadm_id,
    AVG(creatinine_value) AS avg_creatinine_24h
  FROM creatinine_in_first_24h
  GROUP BY hadm_id
)
SELECT 
  PERCENTILE_CONT(avg_creatinine_24h, 0.75) OVER () AS p75_avg_creatinine_24h
FROM avg_creatinine_per_admission
LIMIT 1;