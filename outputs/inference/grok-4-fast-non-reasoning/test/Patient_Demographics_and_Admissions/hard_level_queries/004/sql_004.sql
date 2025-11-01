WITH index_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS row_num
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    CAST(p.subject_id AS STRING) = CAST(a.subject_id AS STRING)
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND a.insurance = 'Medicare'
    AND a.admission_location LIKE '*TRANSFER%'
),
qualified_admissions AS (
  SELECT 
    ia.subject_id,
    ia.hadm_id
  FROM 
    index_admissions ia
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON 
    CAST(ia.subject_id AS STRING) = CAST(d.subject_id AS STRING)
    AND CAST(ia.hadm_id AS STRING) = CAST(d.hadm_id AS STRING)
  WHERE 
    CAST(ia.row_num AS STRING) = '1'
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code LIKE '730.%') 
      OR 
      (d.icd_version = '10' AND d.icd_code LIKE 'M86%')
    )
)
SELECT 
  COUNT(DISTINCT hadm_id) AS num_index_admissions
FROM 
  qualified_admissions;