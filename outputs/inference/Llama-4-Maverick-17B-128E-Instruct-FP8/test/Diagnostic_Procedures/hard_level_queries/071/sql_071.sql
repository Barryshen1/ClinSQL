WITH ich_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE (diag.long_title LIKE '%Intracranial hemorrhage%' AND d.icd_version = 9)
  OR (diag.long_title LIKE '%Intracranial hemorrhage%' AND d.icd_version = 10)
),
icu_stays AS (
  SELECT i.hadm_id, i.stay_id, i.intime, i.outtime, 
         p.anchor_age, p.gender,
         a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 50 AND 60
),
ich_icu_stays AS (
  SELECT icu.*
  FROM icu_stays icu
  JOIN ich_patients ich ON icu.hadm_id = ich.hadm_id
),
procedure_burden AS (
  SELECT stay_id, COUNT(*) as num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE starttime <= (SELECT MIN(intime) FROM ich_icu_stays) + INTERVAL 72 HOUR
  AND stay_id IN (SELECT stay_id FROM ich_icu_stays)
  GROUP BY stay_id
),
stay_procedure_burden AS (
  SELECT i.stay_id, i.intime, i.outtime, i.admittime, i.dischtime, i.hospital_expire_flag, pb.num_procedures
  FROM ich_icu_stays i
  LEFT JOIN procedure_burden pb ON i.stay_id = pb.stay_id
),
general_procedure_burden AS (
  SELECT stay_id, COUNT(*) as num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
  WHERE starttime <= (SELECT MIN(intime) FROM icu_stays) + INTERVAL 72 HOUR
  AND stay_id IN (SELECT stay_id FROM icu_stays)
  GROUP BY stay_id
),
general_stay_procedure_burden AS (
  SELECT i.stay_id, i.intime, i.outtime, i.admittime, i.dischtime, i.hospital_expire_flag, pb.num_procedures
  FROM icu_stays i
  LEFT JOIN general_procedure_burden pb ON i.stay_id = pb.stay_id
)
SELECT 
  'ICH' AS cohort,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS percentile_90,
  MAX(num_procedures) AS max_procedures,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) AS avg_hospital_los,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality
FROM stay_procedure_burden
UNION ALL
SELECT 
  'General' AS cohort,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS percentile_50,
  APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] AS percentile_90,
  MAX(num_procedures) AS max_procedures,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR)) AS avg_hospital_los,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality
FROM general_stay_procedure_burden;