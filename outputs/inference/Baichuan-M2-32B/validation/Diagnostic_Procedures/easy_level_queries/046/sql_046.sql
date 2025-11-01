WITH eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 80 AND 90
),
hospital_procedures AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.icd_code AS procedure_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE dip.icd_version = 9
    AND dip.icd_code LIKE '39.6%'
    AND dip.icd_code != '39.60'  -- Exclude undefined code
),
icu_procedures AS (
  SELECT
    pe.subject_id,
    pe.hadm_id,
    pe.itemid AS procedure_code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE di.category = 'Procedure'
    AND (di.label LIKE '%mechanical circulatory support%'
         OR di.label LIKE '%intra-aortic balloon pump%'
         OR di.label LIKE '%ECMO%'
         OR di.label LIKE '%ventricular assist device%'
         OR di.label LIKE '%cardiopulmonary bypass%'
         OR di.label LIKE '%pump%'
         OR di.label LIKE '%assist device%'
         OR di.label LIKE '%bypass%'
         OR di.label LIKE '%support%')
),
all_procedures AS (
  SELECT subject_id, hadm_id, procedure_code FROM hospital_procedures
  UNION DISTINCT
  SELECT subject_id, hadm_id, CAST(procedure_code AS STRING) FROM icu_procedures  -- Ensure consistent type
),
procedures_per_admission AS (
  SELECT
    ea.hadm_id,
    COUNT(DISTINCT ap.procedure_code) AS distinct_procedures
  FROM eligible_admissions ea
  LEFT JOIN all_procedures ap
    ON ea.subject_id = ap.subject_id AND ea.hadm_id = ap.hadm_id
  GROUP BY ea.hadm_id
)
SELECT MAX(distinct_procedures) AS max_distinct_procedures
FROM procedures_per_admission;