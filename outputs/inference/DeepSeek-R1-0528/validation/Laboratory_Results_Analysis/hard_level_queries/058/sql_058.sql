WITH acs_codes AS (
  -- ICD-10 codes
  SELECT 'I20.0' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'I21%', 10 UNION ALL
  SELECT 'I22%', 10 UNION ALL
  SELECT 'I23%', 10 UNION ALL
  SELECT 'I24.0', 10 UNION ALL
  SELECT 'I24.8', 10 UNION ALL
  SELECT 'I24.9', 10
  UNION ALL
  -- ICD-9 codes
  SELECT '410%', 9 UNION ALL
  SELECT '411.1', 9 UNION ALL
  SELECT '411.81', 9 UNION ALL
  SELECT '413.0', 9 UNION ALL
  SELECT '413.1', 9 UNION ALL
  SELECT '413.9', 9
),
patient_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_year,
    p.anchor_age,
    EXTRACT(YEAR FROM adm.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
),
base_cohort AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    hospital_expire_flag,
    gender,
    age_at_admission
  FROM patient_admissions
  WHERE 
    gender = 'F' 
    AND age_at_admission BETWEEN 40 AND 50
),
acs_cohort AS (
  SELECT 
    b.*
  FROM base_cohort b
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN acs_codes a 
      ON d.icd_version = a.icd_version
      AND (d.icd_code = a.icd_code OR d.icd_code LIKE a.icd_code)
    WHERE b.hadm_id = d.hadm_id
  )
),
general_inpatient_cohort AS (
  SELECT 
    b.*
  FROM base_cohort b
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN acs_codes a 
      ON d.icd_version = a.icd_version
      AND (d.icd_code = a.icd_code OR d.icd_code LIKE a.icd_code)
    WHERE b.hadm_id = d.hadm_id
  )
),
acs_labs AS (
  SELECT 
    acs.hadm_id,
    l.labevent_id
  FROM acs_cohort acs
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON acs.hadm_id = l.hadm_id
    AND l.charttime BETWEEN acs.admittime AND DATETIME_ADD(acs.admittime, INTERVAL 48 HOUR)
  WHERE l.flag = 'critical'
),
acs_instability AS (
  SELECT 
    acs.hadm_id,
    COUNT(l.labevent_id) AS instability_score
  FROM acs_cohort acs
  LEFT JOIN acs_labs l
    ON acs.hadm_id = l.hadm_id
  GROUP BY acs.hadm_id
),
percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90
  FROM acs_instability
),
high_risk_group AS (
  SELECT 
    ai.hadm_id,
    acs.admittime,
    acs.dischtime,
    acs.hospital_expire_flag
  FROM acs_instability ai
  CROSS JOIN percentile_90 p
  INNER JOIN acs_cohort acs
    ON ai.hadm_id = acs.hadm_id
  WHERE ai.instability_score >= p.p90
),
high_risk_critical_labs AS (
  SELECT 
    hrg.hadm_id,
    COUNT(l.labevent_id) AS total_critical_labs
  FROM high_risk_group hrg
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON hrg.hadm_id = l.hadm_id
    AND l.charttime BETWEEN hrg.admittime AND hrg.dischtime
    AND l.flag = 'critical'
  GROUP BY hrg.hadm_id
),
general_critical_labs AS (
  SELECT 
    gic.hadm_id,
    COUNT(l.labevent_id) AS total_critical_labs
  FROM general_inpatient_cohort gic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON gic.hadm_id = l.hadm_id
    AND l.charttime BETWEEN gic.admittime AND gic.dischtime
    AND l.flag = 'critical'
  GROUP BY gic.hadm_id
),
high_risk_agg AS (
  SELECT
    AVG(hrg.hospital_expire_flag) * 100 AS mortality_rate,
    AVG(DATETIME_DIFF(hrg.dischtime, hrg.admittime, DAY)) AS mean_los,
    AVG(hrcl.total_critical_labs) AS critical_lab_rate_high_risk
  FROM high_risk_group hrg
  LEFT JOIN high_risk_critical_labs hrcl
    ON hrg.hadm_id = hrcl.hadm_id
),
general_agg AS (
  SELECT
    AVG(gcl.total_critical_labs) AS critical_lab_rate_general
  FROM general_inpatient_cohort gic
  LEFT JOIN general_critical_labs gcl
    ON gic.hadm_id = gcl.hadm_id
)
SELECT
  h.mortality_rate,
  h.mean_los,
  h.critical_lab_rate_high_risk,
  g.critical_lab_rate_general
FROM high_risk_agg h, general_agg g;