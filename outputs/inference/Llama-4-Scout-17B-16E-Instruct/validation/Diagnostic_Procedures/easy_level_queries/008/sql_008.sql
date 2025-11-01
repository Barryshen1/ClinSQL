WITH 
  patient_procedures AS (
    SELECT 
      p.subject_id,
      COUNT(DISTINCT pi.icd_code) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi ON a.hadm_id = pi.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp ON pi.icd_code = dp.icd_code AND pi.icd_version = dp.icd_version
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 88 AND 98
      AND dp.long_title LIKE '%Echocardiography%'
    GROUP BY 
      p.subject_id
  ),
  ranked_procedures AS (
    SELECT 
      num_procedures,
      ROW_NUMBER() OVER (ORDER BY num_procedures) AS row_num,
      COUNT(*) OVER () AS total_rows
    FROM 
      patient_procedures
  )

SELECT 
  num_procedures
FROM 
  ranked_procedures
WHERE 
  row_num = FLOOR(0.25 * total_rows) + 1;