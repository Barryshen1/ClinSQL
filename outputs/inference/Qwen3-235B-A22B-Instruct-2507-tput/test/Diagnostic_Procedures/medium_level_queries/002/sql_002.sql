WITH tia_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 64 AND 74
    AND LOWER(d.long_title) LIKE '%transient ischemic attack%'
       OR LOWER(d.long_title) LIKE '%tia%'
),
admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu,
    CASE 
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN tia_patients tp ON a.subject_id = tp.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  WHERE DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND a.dischtime IS NOT NULL
),
echo_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS echo_count
  FROM admissions_filtered h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents hc
    ON h.hadm_id = hc.hadm_id
  WHERE hc.hcpcs_cd IN (
    '93306', '93307', '93308', '93312', '93313', '93314', '93315', '93316', '93317', '93318', '93319', '93320', '93321', '93325', '93350', '93351', '93352', '93303', '93304'
  )
  GROUP BY h.hadm_id
),
admissions_with_echo AS (
  SELECT
    af.hadm_id,
    af.had_icu,
    af.los_group,
    COALESCE(ep.echo_count, 0) AS echo_count
  FROM admissions_filtered af
  LEFT JOIN echo_procedures ep ON af.hadm_id = ep.hadm_id
)
SELECT
  los_group,
  had_icu,
  AVG(echo_count) AS mean_echo_per_admission,
  COUNT(*) AS admission_count
FROM admissions_with_echo
WHERE los_group IS NOT NULL
GROUP BY los_group, had_icu
ORDER BY los_group, had_icu;