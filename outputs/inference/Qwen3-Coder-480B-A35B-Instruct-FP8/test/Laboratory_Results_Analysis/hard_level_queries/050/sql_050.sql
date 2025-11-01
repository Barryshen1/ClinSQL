WITH ards_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND d.icd_code = 'J80'
    AND d.icd_version = 10
),

lab_instability AS (
  SELECT
    ac.subject_id,
    COUNT(*) AS instability_score
  FROM
    ards_cohort ac
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    ac.hadm_id = le.hadm_id
  WHERE
    le.charttime >= ac.intime
    AND le.charttime <= DATETIME_ADD(ac.intime, INTERVAL 72 HOUR)
    AND (le.flag = 'abnormal' OR le.valuenum NOT BETWEEN COALESCE(le.ref_range_lower, -99999) AND COALESCE(le.ref_range_upper, 99999))
  GROUP BY
    ac.subject_id
),

percentile_75 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS score_threshold
  FROM
    lab_instability
),

high_instability_ards AS (
  SELECT
    li.subject_id,
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    DATETIME_DIFF(ac.dischtime, ac.admittime, HOUR) / 24.0 AS los_days
  FROM
    lab_instability li
  JOIN
    ards_cohort ac
  ON
    li.subject_id = ac.subject_id
  CROSS JOIN
    percentile_75 p75
  WHERE
    li.instability_score >= p75.score_threshold
),

ards_lab_counts AS (
  SELECT
    ac.subject_id,
    COUNT(*) AS lab_count
  FROM
    ards_cohort ac
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    ac.hadm_id = le.hadm_id
  WHERE
    le.charttime >= ac.intime
    AND le.charttime <= DATETIME_ADD(ac.intime, INTERVAL 72 HOUR)
  GROUP BY
    ac.subject_id
),

non_ards_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.icd_code = 'J80' AND d.icd_version = 10
    )
),

non_ards_lab_counts AS (
  SELECT
    nac.subject_id,
    COUNT(*) AS lab_count
  FROM
    non_ards_cohort nac
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  ON
    nac.hadm_id = le.hadm_id
  WHERE
    le.charttime >= nac.intime
    AND le.charttime <= DATETIME_ADD(nac.intime, INTERVAL 72 HOUR)
  GROUP BY
    nac.subject_id
)

SELECT
  'High Instability ARDS' AS cohort,
  AVG(hi.los_days) AS mean_los,
  AVG(CASE WHEN hi.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
  AVG(al.lab_count) AS avg_critical_labs_per_patient,
  NULL AS avg_critical_labs_non_ards
FROM
  high_instability_ards hi
JOIN
  ards_lab_counts al
ON
  hi.subject_id = al.subject_id

UNION ALL

SELECT
  'Age-Matched Non-ARDS' AS cohort,
  NULL AS mean_los,
  NULL AS mortality_rate,
  NULL AS avg_critical_labs_per_patient,
  AVG(nal.lab_count) AS avg_critical_labs_non_ards
FROM
  non_ards_lab_counts nal;