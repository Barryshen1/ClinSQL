WITH 
pneumonia_patients AS (
  SELECT DISTINCT a.hadm_id, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title LIKE '%Pneumonia%' AND p.gender = 'F'
),

serum_creatinine AS (
  SELECT 
    l.hadm_id, 
    TIMESTAMP_TRUNC(l.charttime, DAY) AS chart_day,
    l.valuenum AS serum_creatinine
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON l.itemid = dli.itemid
  WHERE dli.label = 'Serum Creatinine'
),

daily_avg_creatinine AS (
  SELECT 
    hadm_id,
    chart_day,
    AVG(serum_creatinine) AS avg_creatinine
  FROM serum_creatinine
  GROUP BY hadm_id, chart_day
)

SELECT 
  MIN(avg_creatinine) AS min_24hr_avg_serum_creatinine
FROM pneumonia_patients pp
JOIN daily_avg_creatinine dac ON pp.hadm_id = dac.hadm_id;