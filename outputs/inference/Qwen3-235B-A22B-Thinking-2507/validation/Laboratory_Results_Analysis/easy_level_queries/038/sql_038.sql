WITH stroke_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code 
    AND d.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND (
      LOWER(dd.long_title) LIKE '%cerebral infarction%' 
      OR LOWER(dd.long_title) LIKE '%ischemic stroke%'
    )
)
SELECT 
  MIN(l.valuenum) AS min_hemoglobin
FROM stroke_admissions sa
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
  ON sa.hadm_id = l.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
  ON l.itemid = dl.itemid
WHERE 
  dl.label = 'Hemoglobin'
  AND l.charttime >= sa.admittime
  AND l.charttime <= TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
  AND l.valuenum IS NOT NULL;