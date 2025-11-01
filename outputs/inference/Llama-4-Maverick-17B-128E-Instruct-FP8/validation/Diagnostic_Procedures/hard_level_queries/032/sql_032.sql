WITH cohort AS (
  SELECT p.subject_id, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 66 AND 76
  AND ie.first_careunit = 'True'
  AND ie.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Sepsis%')
  )
),
procedures AS (
  SELECT c.stay_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON c.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),
percentile_procedures AS (
  SELECT APPROX_QUANTILES(num_procedures, 100)[OFFSET(90)] as p90_procedures
  FROM procedures
),
los_mortality AS (
  SELECT c.subject_id, a.hospital_expire_flag, DATETIME_DIFF(a.dischtime, a.admittime, HOUR) as hospital_los
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
)
SELECT '90th Percentile of Procedures' as metric, p90_procedures as value FROM percentile_procedures
UNION ALL
SELECT 'Average Hospital LOS', AVG(hospital_los) FROM los_mortality
UNION ALL
SELECT 'In-Hospital Mortality Rate', AVG(hospital_expire_flag) FROM los_mortality;