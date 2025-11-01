WITH acs_patients AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND (LOWER(di.long_title) LIKE '%acute coronary syndrome%'
         OR LOWER(di.long_title) LIKE '%myocardial infarction%'
         OR LOWER(di.long_title) LIKE '%unstable angina%')
),
nadir_troponin AS (
  SELECT MIN(l.valuenum) AS nadir_troponin
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  JOIN acs_patients a ON l.hadm_id = a.hadm_id
  WHERE LOWER(di.label) LIKE '%troponin%'
    AND l.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY l.subject_id, l.hadm_id
)
SELECT PERCENTILE_CONT(nadir_troponin, 0.25) AS percentile_25
FROM nadir_troponin;