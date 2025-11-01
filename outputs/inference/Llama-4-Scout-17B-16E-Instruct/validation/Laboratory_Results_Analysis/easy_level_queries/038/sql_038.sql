WITH 
  -- Identify ischemic stroke patients with admission time
  ischemic_stroke_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE p.gender = 'M' 
      AND dd.long_title LIKE '%Ischemic stroke%'
  ),

  -- Hemoglobin lab results within 24 hours of admission
  hemoglobin_results AS (
    SELECT 
      i.subject_id, 
      i.hadm_id, 
      le.charttime,
      le.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
    JOIN 
      ischemic_stroke_patients i ON le.hadm_id = i.hadm_id
    WHERE 
      dl.label = 'Hemoglobin'
      AND le.charttime BETWEEN i.admittime AND TIMESTAMP_ADD(i.admittime, INTERVAL 24 HOUR)
  )

-- Find minimum hemoglobin level for each patient
SELECT 
  subject_id, 
  hadm_id, 
  MIN(valuenum) AS min_hemoglobin
FROM 
  hemoglobin_results
GROUP BY 
  subject_id, 
  hadm_id
ORDER BY 
  min_hemoglobin;