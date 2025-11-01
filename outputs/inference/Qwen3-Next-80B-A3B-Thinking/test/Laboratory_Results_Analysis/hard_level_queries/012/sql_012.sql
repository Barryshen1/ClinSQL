WITH amicohort AS (
  SELECT 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND diag.icd_version = 10
        AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%')
    )
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) + p.anchor_age BETWEEN 44 AND 54
),
amicrit AS (
  SELECT 
    a.hadm_id,
    COUNT(lab.labevent_id) AS critical_lab_count
  FROM amicohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
    ON a.hadm_id = lab.hadm_id
  WHERE lab.charttime BETWEEN a.admittime AND a.admittime + INTERVAL 72 HOUR
    AND lab.flag IS NOT NULL
  GROUP BY a.hadm_id
),
general_cohort AS (
  SELECT hadm_id, admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
general_crit AS (
  SELECT 
    g.hadm_id,
    COUNT(lab.labevent_id) AS critical_lab_count
  FROM general_cohort g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab 
    ON g.hadm_id = lab.hadm_id
  WHERE lab.charttime BETWEEN g.admittime AND g.admittime + INTERVAL 72 HOUR
    AND lab.flag IS NOT NULL
  GROUP BY g.hadm_id
)
SELECT
  (SELECT APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(75)] FROM amicrit) AS ami_75th,
  (SELECT APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(75)] FROM general_crit) AS general_75th,
  (SELECT AVG(DATE_DIFF(dischtime, admittime, DAY)) FROM amicohort) AS avg_los,
  (SELECT AVG(CAST(hospital_expire_flag AS INT64)) FROM amicohort) AS mortality_rate;