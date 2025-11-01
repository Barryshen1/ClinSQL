WITH 
  -- Identify HHS patients
  hhs_patients AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.long_title LIKE '%Hyperosmolar%'
    AND a.subject_id IN (
      SELECT subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.patients`
      WHERE gender = 'M' AND anchor_age BETWEEN 58 AND 68
    )
  ),

  -- Calculate LOS and count radiography/CT procedures
  admission_procedures AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
      COUNT(p.icd_code) AS radiography_ct_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
    WHERE dp.long_title LIKE '%Radiology%'  -- Assuming radiography/CT procedures are under radiology
    AND a.hadm_id IN (SELECT hadm_id FROM hhs_patients)
    GROUP BY a.subject_id, a.hadm_id, TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)
  )

SELECT 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4'
    WHEN los BETWEEN 5 AND 7 THEN '5-7'
  END AS los_group,
  COUNT(DISTINCT hadm_id) AS admission_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(radiography_ct_procedures) AS mean_radiography_ct_procedures
FROM admission_procedures
GROUP BY 
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4'
    WHEN los BETWEEN 5 AND 7 THEN '5-7'
  END;