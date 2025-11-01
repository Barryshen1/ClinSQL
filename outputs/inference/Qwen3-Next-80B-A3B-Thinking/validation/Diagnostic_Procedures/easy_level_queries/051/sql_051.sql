WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 41 AND 51
),
icu_procedures AS (
  SELECT pe.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  JOIN target_patients tp ON pe.subject_id = tp.subject_id
  WHERE LOWER(di.label) LIKE '%ecg%' OR LOWER(di.label) LIKE '%telemetry%'
),
hosp_procedures AS (
  SELECT pi.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  JOIN target_patients tp ON pi.subject_id = tp.subject_id
  WHERE LOWER(dip.long_title) LIKE '%ecg%' OR LOWER(dip.long_title) LIKE '%telemetry%'
),
hcpcs_procedures AS (
  SELECT h.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  JOIN target_patients tp ON h.subject_id = tp.subject_id
  WHERE LOWER(dh.short_description) LIKE '%ecg%' OR LOWER(dh.short_description) LIKE '%telemetry%'
),
all_procedures AS (
  SELECT subject_id FROM icu_procedures
  UNION ALL
  SELECT subject_id FROM hosp_procedures
  UNION ALL
  SELECT subject_id FROM hcpcs_procedures
),
patient_counts AS (
  SELECT subject_id, COUNT(*) AS procedure_count
  FROM all_procedures
  GROUP BY subject_id
)
SELECT APPROX_QUANTILES(procedure_count, 100)[OFFSET(75)] AS percentile_75
FROM patient_counts;