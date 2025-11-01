WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
),
ami_hadm AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON e.subject_id = di.subject_id AND e.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE did.long_title LIKE '%myocardial infarction%'
),
critical_flag AS (
  SELECT a.hadm_id,
         MAX(CASE WHEN le.valuenum IS NOT NULL
                   AND le.ref_range_lower IS NOT NULL
                   AND le.ref_range_upper IS NOT NULL
                   AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
                   THEN 1 ELSE 0 END) AS any_critical
  FROM eligible AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = a.hadm_id
   AND le.charttime >= a.admittime
   AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS di
    ON le.itemid = di.itemid
  GROUP BY a.hadm_id
),
combined_admissions AS (
  SELECT e.hadm_id,
         CASE WHEN am.hadm_id IS NOT NULL THEN 'AMI' ELSE 'Control' END AS group_label
  FROM eligible AS e
  LEFT JOIN ami_hadm AS am ON e.hadm_id = am.hadm_id
),
critical_rates AS (
  SELECT group_label,
         COUNT(*) AS n_admissions,
         SUM(COALESCE(cf.any_critical, 0)) AS n_critical
  FROM combined_admissions ca
  LEFT JOIN critical_flag cf ON ca.hadm_id = cf.hadm_id
  GROUP BY group_label
)
SELECT group_label,
       n_admissions,
       n_critical,
       SAFE_DIVIDE(n_critical, n_admissions) AS critical_rate
FROM critical_rates
ORDER BY group_label;