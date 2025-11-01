WITH 
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 42 AND 52
  ),
  valve_procedures AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      d.long_title AS procedure_name
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON 
      p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE 
      d.long_title LIKE '%valve repair%' OR d.long_title LIKE '%valve replacement%'
  ),
  patient_valve_procedures AS (
    SELECT 
      tv.subject_id,
      vp.procedure_name
    FROM 
      target_patients tv
    INNER JOIN 
      valve_procedures vp
    ON 
      tv.subject_id = vp.subject_id
  )

SELECT 
  AVG(distinct_procedures) AS avg_distinct_valve_procedures
FROM (
  SELECT 
    subject_id,
    COUNT(DISTINCT procedure_name) AS distinct_procedures
  FROM 
    patient_valve_procedures
  GROUP BY 
    subject_id
);