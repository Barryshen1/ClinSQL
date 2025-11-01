WITH age_group AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 80 AND 90
),
mech_circ_procedures AS (
  SELECT p.hadm_id, p.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE p.icd_version = 2
    AND (
      LOWER(d.long_title) LIKE '%extracorporeal%' 
      OR LOWER(d.long_title) LIKE '%intra-aortic balloon%'
      OR LOWER(d.long_title) LIKE '%ventricular assist%'
    )
),
procedure_counts AS (
  SELECT 
    ag.hadm_id,
    COUNT(DISTINCT mcp.icd_code) AS num_procedures
  FROM age_group ag
  LEFT JOIN mech_circ_procedures mcp
    ON ag.hadm_id = mcp.hadm_id
  GROUP BY ag.hadm_id
)
SELECT MAX(num_procedures) AS max_distinct_procedures
FROM procedure_counts;