WITH qualifying_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
    AND di.long_title LIKE '%pneumonia%'
),
creatinine_averages AS (
  SELECT qa.hadm_id, AVG(l.valuenum) AS avg_creatinine
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON qa.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  WHERE di.label LIKE '%creatinine%'
    AND l.charttime BETWEEN qa.admittime AND qa.admittime + INTERVAL '24' HOUR
  GROUP BY qa.hadm_id
)
SELECT STDDEV_SAMP(avg_creatinine) AS std_dev_avg_creatinine
FROM creatinine_averages
WHERE avg_creatinine IS NOT NULL;