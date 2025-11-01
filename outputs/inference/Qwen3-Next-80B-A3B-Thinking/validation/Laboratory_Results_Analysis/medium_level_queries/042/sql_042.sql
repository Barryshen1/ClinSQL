WITH chest_pain_admissions AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di 
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1
    AND di.long_title LIKE '%chest pain%'
    AND p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 84 AND 94
),
troponin_first AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  WHERE di.label LIKE '%troponin t%'
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  SUM(hospital_expire_flag) AS deaths
FROM (
  SELECT 
    CASE 
      WHEN tf.valuenum <= 0.04 THEN 'Normal'
      WHEN tf.valuenum > 0.04 AND tf.valuenum <= 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category,
    cpa.hospital_expire_flag
  FROM chest_pain_admissions cpa
  JOIN troponin_first tf 
    ON cpa.hadm_id = tf.hadm_id
  WHERE tf.rn = 1
) 
GROUP BY troponin_category;