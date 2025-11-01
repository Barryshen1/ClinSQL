WITH
  patients AS (
    SELECT subject_id, gender, anchor_age, anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
  ),
  ami_admissions AS (
    SELECT
      adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
      adm.hospital_expire_flag,
      p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN patients p
      ON adm.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND adm.hadm_id IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          (icd_version = 9 AND icd_code LIKE '410%') OR
          (icd_version = 10 AND icd_code LIKE 'I21%')
      )
  ),
  control_admissions AS (
    SELECT
      adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime,
      adm.hospital_expire_flag,
      p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN patients p
      ON adm.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND adm.hadm_id NOT IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          (icd_version = 9 AND icd_code LIKE '410%') OR
          (icd_version = 10 AND icd_code LIKE 'I21%')
      )
  ),
  ami_with_labs AS (
    SELECT
      a.subject_id, a.hadm_id, a.admittime, a.dischtime,
      a.hospital_expire_flag, a.age_at_admission,
      COUNT(le.labevent_id) AS critical_lab_count
    FROM ami_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      AND le.flag = 'panic'
    WHERE a.age_at_admission BETWEEN 38 AND 48
    GROUP BY 1, 2, 3, 4, 5, 6
  ),
  control_with_labs AS (
    SELECT
      c.subject_id, c.hadm_id, c.admittime, c.dischtime,
      c.hospital_expire_flag, c.age_at_admission,
      COUNT(le.labevent_id) AS critical_lab_count
    FROM control_admissions c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON c.hadm_id = le.hadm_id
      AND le.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      AND le.flag = 'panic'
    WHERE c.age_at_admission BETWEEN 38 AND 48
    GROUP BY 1, 2, 3, 4, 5, 6
  ),
  ami_quartiles AS (
    SELECT
      *,
      NTILE(4) OVER (ORDER BY critical_lab_count) AS quartile
    FROM ami_with_labs
  ),
  quartile_summary AS (
    SELECT
      quartile,
      COUNT(*) AS num_patients,
      AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los,
      AVG(hospital_expire_flag) * 100 AS mortality_rate
    FROM ami_quartiles
    GROUP BY quartile
  ),
  overall_rates AS (
    SELECT 'AMI' AS cohort_group, AVG(critical_lab_count) AS avg_critical_labs
    FROM ami_with_labs
    UNION ALL
    SELECT 'Control' AS cohort_group, AVG(critical_lab_count) AS avg_critical_labs
    FROM control_with_labs
  )
SELECT
  quartile,
  num_patients,
  ROUND(avg_los, 2) AS avg_los,
  ROUND(mortality_rate, 2) AS mortality_rate,
  NULL AS cohort_group,
  NULL AS avg_critical_labs
FROM quartile_summary
UNION ALL
SELECT
  NULL AS quartile,
  NULL AS num_patients,
  NULL AS avg_los,
  NULL AS mortality_rate,
  cohort_group,
  ROUND(avg_critical_labs, 2) AS avg_critical_labs
FROM overall_rates
ORDER BY quartile, cohort_group;