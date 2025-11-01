WITH valve_procedures AS (
  SELECT 
    ip.hadm_id,
    COUNT(DISTINCT ip.icd_code) AS distinct_valve_procs
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` ip
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON ip.icd_code = d.icd_code AND ip.icd_version = d.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON ip.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND LOWER(d.long_title) LIKE '%valve%'
    AND (
      LOWER(d.long_title) LIKE '%replace%' 
      OR LOWER(d.long_title) LIKE '%repair%'
      OR LOWER(d.long_title) LIKE '%valvuloplasty%'
    )
  GROUP BY ip.hadm_id
)
SELECT MIN(distinct_valve_procs) AS min_distinct_valve_procedures_per_hospitalization
FROM valve_procedures;