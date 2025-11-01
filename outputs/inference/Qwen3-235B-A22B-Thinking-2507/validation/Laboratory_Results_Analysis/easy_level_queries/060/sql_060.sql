WITH pneumonia_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%pneumonia%'
    )
),
glucose_measurements AS (
  SELECT 
    pa.hadm_id,
    l.valuenum
  FROM pneumonia_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON pa.hadm_id = l.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE 
    l.charttime >= pa.admittime
    AND l.charttime <= pa.admittime + INTERVAL 24 HOUR
    AND LOWER(d.label) = 'glucose'
    AND LOWER(d.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
),
glucose_means AS (
  SELECT 
    hadm_id,
    AVG(valuenum) AS avg_glucose
  FROM glucose_measurements
  GROUP BY hadm_id
)
SELECT 
  (SELECT PERCENTILE_CONT(avg_glucose, 0.75) OVER() 
   FROM glucose_means 
   LIMIT 1) AS percentile_75;