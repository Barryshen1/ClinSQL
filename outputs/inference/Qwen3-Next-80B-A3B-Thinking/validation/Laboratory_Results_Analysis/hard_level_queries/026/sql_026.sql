WITH cohort AS (
  SELECT DISTINCT a.hadm_id, p.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 75 AND 85
    AND di.long_title LIKE '%liver failure%'
),
general_population AS (
  SELECT a.hadm_id, p.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
),
cohort_bilirubin AS (
  SELECT c.hadm_id, MAX(l.valuenum) AS max_bilirubin
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  WHERE l.itemid = 50885
    AND l.charttime BETWEEN c.admittime AND c.admittime + INTERVAL '48' HOUR
  GROUP BY c.hadm_id
),
general_bilirubin AS (
  SELECT g.hadm_id, MAX(l.valuenum) AS max_bilirubin
  FROM general_population g
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON g.hadm_id = l.hadm_id
  WHERE l.itemid = 50885
    AND l.charttime BETWEEN g.admittime AND g.admittime + INTERVAL '48' HOUR
  GROUP BY g.hadm_id
),
cohort_proportion AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN cb.max_bilirubin > 2 THEN cb.hadm_id END) * 1.0 / NULLIF(COUNT(DISTINCT cb.hadm_id), 0) AS proportion_cohort
  FROM cohort_bilirubin cb
),
general_proportion AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN gb.max_bilirubin > 2 THEN gb.hadm_id END) * 1.0 / NULLIF(COUNT(DISTINCT gb.hadm_id), 0) AS proportion_general
  FROM general_bilirubin gb
),
cohort_mortality AS (
  SELECT 
    SUM(hospital_expire_flag) * 1.0 / NULLIF(COUNT(*), 0) AS mortality_rate
  FROM cohort
),
cohort_los AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)) / 24.0 AS avg_los_days
  FROM cohort
),
cohort_max_bilirubin AS (
  SELECT MAX(max_bilirubin) AS max_bilirubin_cohort
  FROM cohort_bilirubin
)
SELECT 
  cm.max_bilirubin_cohort,
  cmor.mortality_rate,
  cl.avg_los_days,
  cp.proportion_cohort,
  gp.proportion_general
FROM cohort_max_bilirubin cm
CROSS JOIN cohort_mortality cmor
CROSS JOIN cohort_los cl
CROSS JOIN cohort_proportion cp
CROSS JOIN general_proportion gp;