WITH stroke_admissions AS (
  SELECT DISTINCT 
      adm.subject_id, 
      adm.hadm_id, 
      adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.subject_id = diag.subject_id 
      AND adm.hadm_id = diag.hadm_id
  WHERE 
      p.gender = 'M'
      AND p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year = 50
      AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
      )
)
SELECT MIN(lab.valuenum) AS min_hemoglobin
FROM stroke_admissions adm
INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.subject_id = lab.subject_id 
    AND adm.hadm_id = lab.hadm_id
WHERE 
    lab.itemid = 51222  -- Hemoglobin
    AND lab.charttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR);