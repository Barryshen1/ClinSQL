WITH hemorrhagic_stroke_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    REGEXP_CONTAINS(long_title, r'hemorrhagic stroke|subarachnoid hemorrhage|intracerebral hemorrhage|intracranial hemorrhage')
    OR REGEXP_CONTAINS(icd_code, r'^(I60|I61|I62|430|431|432)')
  )
),
target_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),
stroke_admissions AS (
  SELECT DISTINCT ta.subject_id, ta.hadm_id, ta.admittime, ta.dischtime, ta.hospital_expire_flag
  FROM target_admissions ta
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ta.hadm_id = d.hadm_id
  JOIN hemorrhagic_stroke_icds h
    ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
),
nonstroke_admissions AS (
  SELECT ta.subject_id, ta.hadm_id, ta.admittime, ta.dischtime, ta.hospital_expire_flag
  FROM target_admissions ta
  WHERE ta.hadm_id NOT IN (
    SELECT hadm_id FROM stroke_admissions
  )
),
lab_instability AS (
  -- For each admission, count distinct lab categories with at least one critical value in first 72h
  SELECT
    sa.subject_id,
    sa.hadm_id,
    COUNT(DISTINCT dl.category) AS lab_instability_score,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM stroke_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
    AND le.flag = 'critical'
    AND le.charttime BETWEEN sa.admittime AND TIMESTAMP_ADD(sa.admittime, INTERVAL 72 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  GROUP BY sa.subject_id, sa.hadm_id
),
lab_instability_nonstroke AS (
  SELECT
    na.subject_id,
    na.hadm_id,
    COUNT(DISTINCT dl.category) AS lab_instability_score,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM nonstroke_admissions na
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON na.hadm_id = le.hadm_id
    AND le.flag = 'critical'
    AND le.charttime BETWEEN na.admittime AND TIMESTAMP_ADD(na.admittime, INTERVAL 72 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  GROUP BY na.subject_id, na.hadm_id
),
p90_lab_instability AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 100)[90] AS p90_lab_instability
  FROM lab_instability
),
stroke_summary AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(CASE WHEN sa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_percent,
    AVG(TIMESTAMP_DIFF(sa.dischtime, sa.admittime, HOUR)/24.0) AS mean_los_days,
    AVG(li.critical_lab_count) AS avg_critical_labs_per_patient
  FROM stroke_admissions sa
  JOIN lab_instability li
    ON sa.hadm_id = li.hadm_id
),
stroke_high_instability AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(CASE WHEN sa.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_percent,
    AVG(TIMESTAMP_DIFF(sa.dischtime, sa.admittime, HOUR)/24.0) AS mean_los_days,
    AVG(li.critical_lab_count) AS avg_critical_labs_per_patient
  FROM stroke_admissions sa
  JOIN lab_instability li
    ON sa.hadm_id = li.hadm_id
  JOIN p90_lab_instability p90
    ON li.lab_instability_score >= p90.p90_lab_instability
),
nonstroke_summary AS (
  SELECT
    COUNT(*) AS n_patients,
    SUM(CASE WHEN na.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS mortality_percent,
    AVG(TIMESTAMP_DIFF(na.dischtime, na.admittime, HOUR)/24.0) AS mean_los_days,
    AVG(li.critical_lab_count) AS avg_critical_labs_per_patient
  FROM nonstroke_admissions na
  JOIN lab_instability_nonstroke li
    ON na.hadm_id = li.hadm_id
),
final_output AS (
  SELECT
    'Hemorrhagic Stroke Cohort' AS cohort,
    p90.p90_lab_instability AS p90_lab_instability_score,
    sh.n_patients AS n_patients_p90plus,
    sh.mortality_percent AS mortality_percent_p90plus,
    sh.mean_los_days AS mean_los_days_p90plus,
    sh.avg_critical_labs_per_patient AS avg_critical_labs_per_patient_p90plus,
    ss.n_patients AS n_patients_total,
    ss.mortality_percent AS mortality_percent_total,
    ss.mean_los_days AS mean_los_days_total,
    ss.avg_critical_labs_per_patient AS avg_critical_labs_per_patient_total
  FROM p90_lab_instability p90
  CROSS JOIN stroke_high_instability sh
  CROSS JOIN stroke_summary ss
  UNION ALL
  SELECT
    'Age-matched Non-Stroke Cohort' AS cohort,
    NULL AS p90_lab_instability_score,
    NULL AS n_patients_p90plus,
    NULL AS mortality_percent_p90plus,
    NULL AS mean_los_days_p90plus,
    NULL AS avg_critical_labs_per_patient_p90plus,
    ns.n_patients AS n_patients_total,
    ns.mortality_percent AS mortality_percent_total,
    ns.mean_los_days AS mean_los_days_total,
    ns.avg_critical_labs_per_patient AS avg_critical_labs_per_patient_total
  FROM nonstroke_summary ns
)

SELECT * FROM final_output;