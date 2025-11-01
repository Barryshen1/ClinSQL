WITH copd_admissions AS (
  SELECT a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND di.long_title LIKE '%COPD%'
),
creatinine_24h AS (
  SELECT c.hadm_id, AVG(l.valuenum) AS avg_creatinine
  FROM copd_admissions c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.fluid = 'SERUM'
    AND dl.label LIKE '%creatinine%'
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '24' HOUR
  GROUP BY c.hadm_id
)
SELECT PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY avg_creatinine) AS percentile_75
FROM creatinine_24h
WHERE avg_creatinine IS NOT NULL;