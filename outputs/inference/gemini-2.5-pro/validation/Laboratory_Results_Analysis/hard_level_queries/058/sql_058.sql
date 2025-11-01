WITH
  acs_icd_codes AS (
    -- Define ICD codes for Acute Coronary Syndrome (ACS)
    SELECT
      icd_code,
      icd_version
    FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
    WHERE
      (
        icd_version = 9
        AND (
          icd_code LIKE '410%' -- Acute Myocardial Infarction
          OR icd_code LIKE '411.1%' -- Unstable Angina
        )
      )
      OR (
        icd_version = 10
        AND (
          icd_code LIKE 'I21%' -- Acute Myocardial Infarction
          OR icd_code LIKE 'I20.0%' -- Unstable Angina
          OR icd_code LIKE 'I24.0%' -- Coronary thrombosis not resulting in MI
        )
      )
  ),

  acs_cohort AS (
    -- Identify female patients aged 40-50 admitted with ACS
    SELECT DISTINCT
      a.hadm_id,
      a.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'F'
      AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 40 AND 50
      AND EXISTS (
        SELECT 1
        FROM acs_icd_codes
        WHERE
          acs_icd_codes.icd_code = d.icd_code
          AND acs_icd_codes.icd_version = d.icd_version
      )
  ),

  lab_instability_scores AS (
    -- Calculate the instability score: count of abnormal labs in the first 48 hours
    SELECT
      c.hadm_id,
      COUNT(l.labevent_id) AS instability_score
    FROM acs_cohort AS c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS l
      ON c.hadm_id = l.hadm_id
      AND l.charttime <= DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
      AND l.flag = 'abnormal'
    GROUP BY
      c.hadm_id
  ),

  instability_threshold AS (
    -- Determine the 90th percentile of the instability score
    SELECT
      APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
    FROM lab_instability_scores
  ),

  patient_groups AS (
    -- Classify all hospital admissions into two groups
    SELECT
      adm.hadm_id,
      CASE
        WHEN lis.instability_score >= (
          SELECT p90_score FROM instability_threshold
        )
          THEN 'High-Risk ACS (>=P90)'
        ELSE 'General Population'
      END AS patient_group
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    LEFT JOIN lab_instability_scores AS lis
      ON adm.hadm_id = lis.hadm_id
  ),

  lab_stats_per_admission AS (
    -- Calculate total and abnormal labs for the entire stay for all patients
    SELECT
      hadm_id,
      COUNT(labevent_id) AS total_labs,
      COUNTIF(flag = 'abnormal') AS abnormal_labs
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    GROUP BY
      hadm_id
  )

-- Final reporting of metrics for the two groups
SELECT
  pg.patient_group,
  COUNT(DISTINCT adm.hadm_id) AS num_patients,
  AVG(adm.hospital_expire_flag) AS mortality_rate,
  AVG(
    DATETIME_DIFF(COALESCE(adm.dischtime, adm.deathtime), adm.admittime, HOUR) / 24.0
  ) AS mean_los_days,
  SAFE_DIVIDE(SUM(ls.abnormal_labs), SUM(ls.total_labs)) AS critical_lab_rate
FROM patient_groups AS pg
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  ON pg.hadm_id = adm.hadm_id
LEFT JOIN lab_stats_per_admission AS ls
  ON pg.hadm_id = ls.hadm_id
GROUP BY
  pg.patient_group
ORDER BY
  pg.patient_group DESC;