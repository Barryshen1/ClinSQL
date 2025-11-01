WITH patient_age AS (
  SELECT
    subject_id,
    (anchor_year - anchor_age) AS birth_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
),
admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    EXTRACT(YEAR FROM a.admittime) - p.birth_year AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_age p ON a.subject_id = p.subject_id
),
eligible_admissions AS (
  SELECT
    subject_id,
    hadm_id
  FROM admissions_with_age
  WHERE age_at_admission BETWEEN 81 AND 91
),
eligible_patients AS (
  SELECT DISTINCT subject_id
  FROM eligible_admissions
),
icd_procedures AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.icd_code AS code,
    'ICD' AS system
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE REGEXP_CONTAINS(LOWER(d.long_title), r'ecg|electrocardiogram|telemetry')
),
hcpcs_procedures AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hcpcs_cd AS code,
    'HCPCS' AS system
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE REGEXP_CONTAINS(LOWER(d.long_description), r'ecg|electrocardiogram|telemetry')
  OR REGEXP_CONTAINS(LOWER(d.short_description), r'ecg|electrocardiogram|telemetry')
),
all_procedures AS (
  SELECT subject_id, hadm_id, code, system FROM icd_procedures
  UNION ALL
  SELECT subject_id, hadm_id, code, system FROM hcpcs_procedures
),
filtered_procedures AS (
  SELECT
    ap.subject_id,
    ap.hadm_id,
    p.code,
    p.system
  FROM all_procedures p
  INNER JOIN eligible_admissions ap
    ON p.subject_id = ap.subject_id AND p.hadm_id = ap.hadm_id
),
patient_counts AS (
  SELECT
    ep.subject_id,
    COUNT(DISTINCT CONCAT(p.code, '|', p.system)) AS distinct_procedure_count
  FROM eligible_patients ep
  LEFT JOIN filtered_procedures p ON ep.subject_id = p.subject_id
  GROUP BY ep.subject_id
)
SELECT
  STDDEV(distinct_procedure_count) AS sd
FROM patient_counts;