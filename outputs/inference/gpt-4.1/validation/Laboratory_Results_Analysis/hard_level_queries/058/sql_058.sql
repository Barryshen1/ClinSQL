WITH
-- ACS ICD codes (ICD-10 and ICD-9)
acs_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I20') OR
      REGEXP_CONTAINS(icd_code, r'^I21') OR
      REGEXP_CONTAINS(icd_code, r'^I22') OR
      REGEXP_CONTAINS(icd_code, r'^I23')
    ))
    OR
    (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^410') OR
      REGEXP_CONTAINS(icd_code, r'^411')
    ))
),

-- Female inpatients age 40-50
female_40_50 AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- ACS admissions
acs_admissions AS (
  SELECT DISTINCT f.*
  FROM female_40_50 f
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON f.hadm_id = d.hadm_id
  JOIN acs_icd acs
    ON d.icd_code = acs.icd_code AND d.icd_version = acs.icd_version
),

-- Instability score per admission: count abnormal labs in first 48h
acs_lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(
      (
        l.flag = 'abnormal'
        OR (SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL AND (
          (l.ref_range_lower IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
          OR
          (l.ref_range_upper IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
        ))
      )
    ) AS instability_score,
    COUNTIF(l.flag = 'critical') AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM acs_admissions a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id
),

-- 90th percentile instability score in ACS cohort
acs_90th_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS instability_score_90th
  FROM acs_lab_scores
),

-- ACS cohort at/above 90th percentile
acs_high_instability AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.instability_score,
    s.critical_lab_count,
    s.total_lab_count,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM acs_lab_scores s
  JOIN acs_admissions a
    ON s.subject_id = a.subject_id AND s.hadm_id = a.hadm_id
  CROSS JOIN acs_90th_percentile p
  WHERE s.instability_score >= p.instability_score_90th
),

-- General cohort (female, 40-50, all admissions)
general_lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(
      (
        l.flag = 'abnormal'
        OR (SAFE_CAST(l.valuenum AS FLOAT64) IS NOT NULL AND (
          (l.ref_range_lower IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) < SAFE_CAST(l.ref_range_lower AS FLOAT64))
          OR
          (l.ref_range_upper IS NOT NULL AND SAFE_CAST(l.valuenum AS FLOAT64) > SAFE_CAST(l.ref_range_upper AS FLOAT64))
        ))
      )
    ) AS instability_score,
    COUNTIF(l.flag = 'critical') AS critical_lab_count,
    COUNT(*) AS total_lab_count,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM female_40_50 a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
    AND l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
),

-- General cohort at/above ACS 90th percentile
general_high_instability AS (
  SELECT *
  FROM general_lab_scores
  CROSS JOIN acs_90th_percentile p
  WHERE instability_score >= p.instability_score_90th
)

-- Final output
SELECT
  'ACS cohort (>=90th percentile)' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(los) AS mean_los_days,
  SAFE_DIVIDE(SUM(critical_lab_count), SUM(total_lab_count)) AS critical_lab_rate
FROM acs_high_instability

UNION ALL

SELECT
  'General cohort (>=ACS 90th percentile)' AS cohort,
  COUNT(*) AS n_admissions,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(los) AS mean_los_days,
  SAFE_DIVIDE(SUM(critical_lab_count), SUM(total_lab_count)) AS critical_lab_rate
FROM general_high_instability;