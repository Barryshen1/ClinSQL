WITH 
cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),

ecmo_icd AS (
  SELECT 
    subject_id,
    hadm_id,
    'ECMO' AS procedure_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 10
    AND icd_code LIKE '5A1522%'
),

iabp_icd AS (
  SELECT 
    subject_id,
    hadm_id,
    'IABP' AS procedure_type
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
  WHERE icd_version = 10
    AND icd_code = '5A02210'
),

ecmo_hcpcs AS (
  SELECT 
    subject_id,
    hadm_id,
    'ECMO' AS procedure_type
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN ('33975','33976','33977','33978','33979','33980','33981','33982','33983','33984')
),

mcs_icu AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    CASE 
      WHEN LOWER(d.label) LIKE '%ecmo%' OR LOWER(d.label) LIKE '%extracorporeal%' THEN 'ECMO'
      WHEN LOWER(d.label) LIKE '%iabp%' OR LOWER(d.label) LIKE '%intra-aortic balloon%' THEN 'IABP'
      ELSE NULL
    END AS procedure_type
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON p.itemid = d.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.stay_id = i.stay_id
  WHERE d.category = 'Procedure'
    AND (LOWER(d.label) LIKE '%ecmo%' 
         OR LOWER(d.label) LIKE '%extracorporeal%' 
         OR LOWER(d.label) LIKE '%iabp%' 
         OR LOWER(d.label) LIKE '%intra-aortic balloon%')
),

all_mcs AS (
  SELECT subject_id, hadm_id, procedure_type
  FROM ecmo_icd
  UNION DISTINCT
  SELECT subject_id, hadm_id, procedure_type
  FROM iabp_icd
  UNION DISTINCT
  SELECT subject_id, hadm_id, procedure_type
  FROM ecmo_hcpcs
  UNION DISTINCT
  SELECT subject_id, hadm_id, procedure_type
  FROM mcs_icu
  WHERE procedure_type IS NOT NULL
),

patient_procedure_counts AS (
  SELECT 
    c.subject_id,
    COUNT(DISTINCT a.procedure_type) AS mcs_count
  FROM cohort c
  LEFT JOIN all_mcs a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
  GROUP BY c.subject_id
)

SELECT 
  APPROX_QUANTILES(mcs_count, 100)[OFFSET(25)] AS percentile_25
FROM patient_procedure_counts;