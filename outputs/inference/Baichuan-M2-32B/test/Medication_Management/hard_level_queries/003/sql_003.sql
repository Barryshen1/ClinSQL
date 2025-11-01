WITH base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 39 AND 49
),
status_epilepticus_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title LIKE '%status epilepticus%' 
     OR d.icd_code LIKE 'G40.3%'
),
qt_drugs_list AS (
  SELECT 'amiodarone' AS drug
  UNION ALL SELECT 'quinidine'
  UNION ALL SELECT 'dofetilide'
  UNION ALL SELECT 'sotalol'
  UNION ALL SELECT 'dronedarone'
  UNION ALL SELECT 'ibutilide'
  UNION ALL SELECT 'cisapride'
  UNION ALL SELECT 'halofantrine'
  UNION ALL SELECT 'moxifloxacin'
  UNION ALL SELECT 'erythromycin'
),
bleeding_drugs_list AS (
  SELECT 'warfarin' AS drug
  UNION ALL SELECT 'aspirin'
  UNION ALL SELECT 'clopidogrel'
  UNION ALL SELECT 'heparin'
  UNION ALL SELECT 'enoxaparin'
  UNION ALL SELECT 'rivaroxaban'
  UNION ALL SELECT 'apixaban'
  UNION ALL SELECT 'dabigatran'
  UNION ALL SELECT 'desmopressin'
  UNION ALL SELECT 'abciximab'
),
meds_first24h AS (
  SELECT
    p.hadm_id,
    p.subject_id,
    COUNT(DISTINCT p.drug) AS num_distinct_meds
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN base_admissions b 
    ON p.hadm_id = b.hadm_id
  WHERE p.starttime BETWEEN b.admittime AND DATETIME_ADD(b.admittime, INTERVAL 24 HOUR)
  GROUP BY p.hadm_id, p.subject_id
),
admissions_with_meds AS (
  SELECT
    b.*,
    COALESCE(m.num_distinct_meds, 0) AS med_complexity
  FROM base_admissions b
  LEFT JOIN meds_first24h m 
    ON b.hadm_id = m.hadm_id
),
admissions_with_flags AS (
  SELECT
    a.*,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS status_epilepticus,
    CASE WHEN q.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_qt_drug,
    CASE WHEN b.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_bleeding_drug
  FROM admissions_with_meds a
  LEFT JOIN status_epilepticus_adm s 
    ON a.hadm_id = s.hadm_id
  LEFT JOIN (
    SELECT DISTINCT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN qt_drugs_list q 
      ON p.drug = q.drug
    INNER JOIN base_admissions b 
      ON p.hadm_id = b.hadm_id
    WHERE p.starttime BETWEEN b.admittime AND DATETIME_ADD(b.admittime, INTERVAL 24 HOUR)
  ) q ON a.hadm_id = q.hadm_id
  LEFT JOIN (
    SELECT DISTINCT p.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    INNER JOIN bleeding_drugs_list b 
      ON p.drug = b.drug
    INNER JOIN base_admissions b2 
      ON p.hadm_id = b2.hadm_id
    WHERE p.starttime BETWEEN b2.admittime AND DATETIME_ADD(b2.admittime, INTERVAL 24 HOUR)
  ) b ON a.hadm_id = b.hadm_id
),
groups AS (
  SELECT
    hadm_id,
    subject_id,
    med_complexity,
    los,
    hospital_expire_flag,
    CASE
      WHEN status_epilepticus = 1 THEN 'status_epilepticus'
      WHEN has_qt_drug = 1 THEN 'qt_drug'
      WHEN has_bleeding_drug = 1 THEN 'bleeding_drug'
      ELSE 'general'
    END AS group_label
  FROM admissions_with_flags
),
group_summary AS (
  SELECT
    group_label,
    AVG(med_complexity) AS avg_med_complexity,
    AVG(los) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate,
    COUNT(*) AS num_patients
  FROM groups
  GROUP BY group_label
),
status_epilepticus_patients AS (
  SELECT
    hadm_id,
    med_complexity,
    los,
    hospital_expire_flag,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS percentile_rank
  FROM groups
  WHERE group_label = 'status_epilepticus'
),
top_quartile_status AS (
  SELECT
    AVG(los) AS avg_los_top_quartile,
    AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate_top_quartile
  FROM status_epilepticus_patients
  WHERE percentile_rank >= 0.75
)
SELECT * FROM group_summary
UNION ALL
SELECT 
  'top_quartile_status_epilepticus' AS group_label, 
  NULL AS avg_med_complexity, 
  avg_los_top_quartile AS avg_los, 
  mortality_rate_top_quartile AS mortality_rate, 
  NULL AS num_patients
FROM top_quartile_status;