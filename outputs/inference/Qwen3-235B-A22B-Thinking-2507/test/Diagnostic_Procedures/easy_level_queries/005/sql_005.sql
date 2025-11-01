WITH echo_procedures AS (
  -- Echocardiography from procedures_icd (inpatient)
  SELECT 
    p.subject_id,
    a.admittime AS procedure_date
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON pi.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE LOWER(d.long_title) LIKE '%echocardiography%'
    AND p.gender = 'M'
  
  UNION ALL
  
  -- Echocardiography from hcpcsevents (outpatient)
  SELECT 
    p.subject_id,
    h.chartdate AS procedure_date
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d 
    ON h.hcpcs_cd = d.code
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON h.subject_id = p.subject_id
  WHERE (h.hcpcs_cd IN ('93306','93307','93308','93312','93313','93314','93315','93316','93317','93318','93320','93321','93325','93350','93351','93352','93353')
         OR LOWER(d.long_description) LIKE '%echocardiography%'
         OR LOWER(d.short_description) LIKE '%echocardiography%')
    AND p.gender = 'M'
),

age_filtered AS (
  SELECT
    subject_id,
    procedure_date,
    p.anchor_age + (EXTRACT(YEAR FROM procedure_date) - p.anchor_year) AS age_at_procedure
  FROM echo_procedures ep
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    USING (subject_id)
  WHERE p.anchor_age + (EXTRACT(YEAR FROM procedure_date) - p.anchor_year) BETWEEN 57 AND 67
),

procedure_counts AS (
  SELECT
    subject_id,
    COUNT(*) AS num_echo
  FROM age_filtered
  GROUP BY subject_id
)

SELECT
  PERCENTILE_CONT(num_echo, 0.75) OVER () AS p75
FROM procedure_counts
LIMIT 1;