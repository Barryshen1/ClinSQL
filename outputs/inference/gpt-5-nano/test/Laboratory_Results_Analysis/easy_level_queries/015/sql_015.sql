WITH pneumonia_female_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcd
    ON dcd.icd_code = di.icd_code AND dcd.icd_version = di.icd_version
  WHERE LOWER(dcd.long_title) LIKE '%pneumonia%'
    AND p.gender = 'F'
),
creatinine_24h_per_admission AS (
  SELECT pf.subject_id, pf.hadm_id,
         AVG(l.valuenum) AS creat24h_avg
  FROM pneumonia_female_admissions AS pf
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON a.subject_id = pf.subject_id AND a.hadm_id = pf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON l.subject_id = pf.subject_id AND l.hadm_id = pf.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON dli.itemid = l.itemid
  WHERE l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
    AND LOWER(dli.label) LIKE '%creatinine%'
  GROUP BY pf.subject_id, pf.hadm_id
)
SELECT MIN(creat24h_avg) AS min_24h_creatinine_mg_per_dL
FROM creatinine_24h_per_admission
WHERE creat24h_avg IS NOT NULL;