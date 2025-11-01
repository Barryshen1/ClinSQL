WITH cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON diag.icd_code = icd.icd_code
    AND diag.icd_version = icd.icd_version
  WHERE p.gender = 'M'
    AND LOWER(icd.long_title) LIKE '%pneumonia%'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 BETWEEN 45 AND 55
),
avg_creatinine AS (
  SELECT 
    c.hadm_id,
    AVG(le.valuenum) AS avg_serum_creat
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = c.hadm_id
  WHERE le.itemid = 220615
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
    AND le.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
)
SELECT STDDEV(avg_serum_creat) AS sd_of_avg_serum_creatinine
FROM avg_creatinine;