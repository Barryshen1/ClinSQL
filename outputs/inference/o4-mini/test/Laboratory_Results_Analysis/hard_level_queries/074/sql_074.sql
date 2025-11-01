WITH adms AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
),

hf_hadm AS (
  -- Identify admissions with any heart failure diagnosis (ICD9 428.* or ICD10 I50.*)
  SELECT DISTINCT hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING (icd_code, icd_version)
  WHERE
    (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
    OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
),

labs_crit AS (
  -- Count distinct critically abnormal lab itemids in first 72h of each admission
  SELECT
    le.hadm_id,
    COUNT(DISTINCT le.itemid) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN adms a
      ON le.hadm_id = a.hadm_id
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.charttime BETWEEN a.admittime
      AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY
    le.hadm_id
),

adms_scores AS (
  -- Combine admissions with their instability scores
  SELECT
    a.*,
    COALESCE(l.instability_score, 0) AS instability_score,
    CASE WHEN COALESCE(l.instability_score, 0) >= 1 THEN 1 ELSE 0 END AS critical_flag
  FROM
    adms a
    LEFT JOIN labs_crit l USING (hadm_id)
),

cohort AS (
  -- Assign each admission to one of two cohorts
  SELECT
    hadm_id,
    los_days,
    hospital_expire_flag,
    instability_score,
    critical_flag,
    CASE
      WHEN gender = 'M'
        AND anchor_age BETWEEN 37 AND 47
        AND hadm_id IN (SELECT hadm_id FROM hf_hadm)
      THEN 'male_hf_37_47'
      ELSE 'all_inpatients'
    END AS cohort
  FROM
    adms_scores
)

SELECT
  c.cohort,
  COUNT(*) AS n_admissions,
  MAX(c.instability_score) AS max_instability_score,
  ROUND(AVG(c.critical_flag), 4) AS critical_event_rate,
  ROUND(AVG(c.los_days), 2) AS avg_los_days,
  ROUND(AVG(c.hospital_expire_flag), 4) AS mortality_rate
FROM
  cohort AS c
GROUP BY
  c.cohort
ORDER BY
  c.cohort;