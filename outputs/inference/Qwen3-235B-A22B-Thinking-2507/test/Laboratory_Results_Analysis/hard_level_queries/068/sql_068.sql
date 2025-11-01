WITH admissions_cohort AS (
  SELECT 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 89 AND 99
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND diag.icd_code = 'R6521'
        AND diag.icd_version = 10
    )
),
admissions_comparison AS (
  SELECT 
    adm.hadm_id,
    adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND (pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) BETWEEN 89 AND 99
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND diag.icd_code = 'R6521'
        AND diag.icd_version = 10
    )
),
lactate_cohort AS (
  SELECT 
    adm.hadm_id,
    MAX(lab.valuenum) AS max_lactate
  FROM admissions_cohort adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
    AND lab.charttime >= adm.admittime
    AND lab.charttime <= adm.admittime + INTERVAL '48' HOUR
  WHERE lab.itemid = 50813  -- Lactate
    AND lab.valuenum IS NOT NULL
  GROUP BY adm.hadm_id
),
abn_cohort AS (
  SELECT 
    adm.hadm_id,
    COUNT(*) AS abn_count
  FROM admissions_cohort adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
    AND lab.charttime >= adm.admittime
    AND lab.charttime <= adm.admittime + INTERVAL '48' HOUR
  WHERE 
    lab.valuenum IS NOT NULL
    AND lab.ref_range_lower IS NOT NULL
    AND lab.ref_range_upper IS NOT NULL
    AND (lab.valuenum < lab.ref_range_lower OR lab.valuenum > lab.ref_range_upper)
  GROUP BY adm.hadm_id
),
abn_comparison AS (
  SELECT 
    adm.hadm_id,
    COUNT(*) AS abn_count
  FROM admissions_comparison adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` lab
    ON adm.hadm_id = lab.hadm_id
    AND lab.charttime >= adm.admittime
    AND lab.charttime <= adm.admittime + INTERVAL '48' HOUR
  WHERE 
    lab.valuenum IS NOT NULL
    AND lab.ref_range_lower IS NOT NULL
    AND lab.ref_range_upper IS NOT NULL
    AND (lab.valuenum < lab.ref_range_lower OR lab.valuenum > lab.ref_range_upper)
  GROUP BY adm.hadm_id
)
SELECT 
  (SELECT PERCENTILE_CONT(max_lactate, 0.25) 
   FROM lactate_cohort) AS instability_q1,
  (SELECT PERCENTILE_CONT(max_lactate, 0.5) 
   FROM lactate_cohort) AS instability_median,
  (SELECT PERCENTILE_CONT(max_lactate, 0.75) 
   FROM lactate_cohort) AS instability_q3,
  (SELECT PERCENTILE_CONT(max_lactate, 0.75) 
   FROM lactate_cohort) 
  - 
  (SELECT PERCENTILE_CONT(max_lactate, 0.25) 
   FROM lactate_cohort) AS instability_iqr,
  (SELECT AVG(COALESCE(abn_count, 0)) 
   FROM admissions_cohort 
   LEFT JOIN abn_cohort USING (hadm_id)) AS abn_freq_cohort,
  (SELECT AVG(COALESCE(abn_count, 0)) 
   FROM admissions_comparison 
   LEFT JOIN abn_comparison USING (hadm_id)) AS abn_freq_comparison,
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) 
   FROM admissions_cohort) AS cohort_los,
  (SELECT AVG(hospital_expire_flag) 
   FROM admissions_cohort) AS cohort_mortality;