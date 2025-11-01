WITH admissions_of_interest AS (
  SELECT 
    p.subject_id, 
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 43 AND 53
),
patients_of_interest AS (
  SELECT DISTINCT subject_id
  FROM admissions_of_interest
),
icd_procedures AS (
  SELECT 
    p.subject_id, 
    CASE 
      WHEN LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%' OR LOWER(d.long_title) LIKE '%ecmo%' THEN 'ECMO'
      WHEN LOWER(d.long_title) LIKE '%intra-aortic balloon%' OR LOWER(d.long_title) LIKE '%iabp%' THEN 'IABP'
      WHEN LOWER(d.long_title) LIKE '%ventricular assist%' OR LOWER(d.long_title) LIKE '%vad%' OR LOWER(d.long_title) LIKE '%lvad%' OR LOWER(d.long_title) LIKE '%rvad%' OR LOWER(d.long_title) LIKE '%bivad%' THEN 'VAD'
      WHEN LOWER(d.long_title) LIKE '%impella%' THEN 'Impella'
      ELSE NULL 
    END AS procedure_concept
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    JOIN admissions_of_interest aoi 
      ON p.subject_id = aoi.subject_id AND p.hadm_id = aoi.hadm_id
  WHERE 
    (LOWER(d.long_title) LIKE '%extracorporeal membrane oxygenation%' OR
     LOWER(d.long_title) LIKE '%ecmo%' OR
     LOWER(d.long_title) LIKE '%intra-aortic balloon%' OR
     LOWER(d.long_title) LIKE '%iabp%' OR
     LOWER(d.long_title) LIKE '%ventricular assist%' OR
     LOWER(d.long_title) LIKE '%vad%' OR
     LOWER(d.long_title) LIKE '%lvad%' OR
     LOWER(d.long_title) LIKE '%rvad%' OR
     LOWER(d.long_title) LIKE '%bivad%' OR
     LOWER(d.long_title) LIKE '%impella%')
),
icu_procedures AS (
  SELECT 
    p.subject_id, 
    CASE 
      WHEN LOWER(d.label) LIKE '%ecmo%' THEN 'ECMO'
      WHEN LOWER(d.label) LIKE '%intra-aortic balloon%' OR LOWER(d.label) LIKE '%iabp%' THEN 'IABP'
      WHEN LOWER(d.label) LIKE '%ventricular assist%' OR LOWER(d.label) LIKE '%vad%' OR LOWER(d.label) LIKE '%lvad%' OR LOWER(d.label) LIKE '%rvad%' OR LOWER(d.label) LIKE '%bivad%' THEN 'VAD'
      WHEN LOWER(d.label) LIKE '%impella%' THEN 'Impella'
      ELSE NULL 
    END AS procedure_concept
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` p
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d 
      ON p.itemid = d.itemid
    JOIN admissions_of_interest aoi 
      ON p.subject_id = aoi.subject_id AND p.hadm_id = aoi.hadm_id
  WHERE 
    (LOWER(d.label) LIKE '%ecmo%' OR
     LOWER(d.label) LIKE '%intra-aortic balloon%' OR
     LOWER(d.label) LIKE '%iabp%' OR
     LOWER(d.label) LIKE '%ventricular assist%' OR
     LOWER(d.label) LIKE '%vad%' OR
     LOWER(d.label) LIKE '%lvad%' OR
     LOWER(d.label) LIKE '%rvad%' OR
     LOWER(d.label) LIKE '%bivad%' OR
     LOWER(d.label) LIKE '%impella%')
),
all_procedures AS (
  SELECT subject_id, procedure_concept
  FROM icd_procedures
  WHERE procedure_concept IS NOT NULL
  UNION DISTINCT
  SELECT subject_id, procedure_concept
  FROM icu_procedures
  WHERE procedure_concept IS NOT NULL
),
patient_procedure_counts AS (
  SELECT 
    po.subject_id,
    COUNT(DISTINCT ap.procedure_concept) AS num_distinct_procedures
  FROM 
    patients_of_interest po
    LEFT JOIN all_procedures ap 
      ON po.subject_id = ap.subject_id
  GROUP BY po.subject_id
)
SELECT 
  APPROX_QUANTILES(num_distinct_procedures, 100)[OFFSET(25)] AS percentile_25
FROM patient_procedure_counts;