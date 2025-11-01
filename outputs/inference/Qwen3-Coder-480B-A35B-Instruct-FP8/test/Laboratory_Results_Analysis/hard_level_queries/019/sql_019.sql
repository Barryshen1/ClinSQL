WITH cohort_ap_male_63_73 AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime,
    a.hospital_expire_flag,
    icu.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx ON a.hadm_id = dx.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(d.long_title) LIKE '%acute pancreatitis%'
),

lab_instability_score AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.icu_intime,
    COUNT(*) AS instability_score
  FROM
    cohort_ap_male_63_73 c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le ON c.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON le.itemid = d.itemid
  WHERE
    le.charttime BETWEEN c.icu_intime AND DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      (d.label = 'WBC' AND (le.valuenum < 4 OR le.valuenum > 12)) OR
      (d.label = 'Lactate' AND le.valuenum > 2) OR
      (d.label = 'Creatinine' AND le.valuenum > 1.2) OR
      (d.label = 'Bilirubin' AND le.valuenum > 1.2) OR
      (d.label = 'AST' AND le.valuenum > 40) OR
      (d.label = 'ALT' AND le.valuenum > 40)
    )
  GROUP BY
    c.subject_id, c.hadm_id, c.stay_id, c.icu_intime
),

score_percentile AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.9) OVER() AS p90_score
  FROM
    lab_instability_score
  LIMIT 1
),

patients_p90 AS (
  SELECT
    lis.*,
    c.hospital_expire_flag,
    c.icu_los
  FROM
    lab_instability_score lis
  JOIN
    cohort_ap_male_63_73 c ON lis.stay_id = c.stay_id
  CROSS JOIN
    score_percentile sp
  WHERE
    lis.instability_score >= sp.p90_score
),

general_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    icu.stay_id,
    icu.intime AS icu_intime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
),

critical_labs_p90 AS (
  SELECT
    'p90' AS cohort,
    d.label AS lab_name,
    COUNT(*) AS total_abnormal,
    COUNT(DISTINCT lis.stay_id) AS patient_count
  FROM
    patients_p90 lis
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le ON lis.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON le.itemid = d.itemid
  WHERE
    le.charttime BETWEEN lis.icu_intime AND DATETIME_ADD(lis.icu_intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      (d.label = 'WBC' AND (le.valuenum < 4 OR le.valuenum > 12)) OR
      (d.label = 'Lactate' AND le.valuenum > 2) OR
      (d.label = 'Creatinine' AND le.valuenum > 1.2) OR
      (d.label = 'Bilirubin' AND le.valuenum > 1.2) OR
      (d.label = 'AST' AND le.valuenum > 40) OR
      (d.label = 'ALT' AND le.valuenum > 40)
    )
  GROUP BY
    d.label
),

critical_labs_general AS (
  SELECT
    'general' AS cohort,
    d.label AS lab_name,
    COUNT(*) AS total_abnormal,
    COUNT(DISTINCT gi.stay_id) AS patient_count
  FROM
    general_inpatients gi
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le ON gi.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON le.itemid = d.itemid
  WHERE
    le.charttime BETWEEN gi.icu_intime AND DATETIME_ADD(gi.icu_intime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      (d.label = 'WBC' AND (le.valuenum < 4 OR le.valuenum > 12)) OR
      (d.label = 'Lactate' AND le.valuenum > 2) OR
      (d.label = 'Creatinine' AND le.valuenum > 1.2) OR
      (d.label = 'Bilirubin' AND le.valuenum > 1.2) OR
      (d.label = 'AST' AND le.valuenum > 40) OR
      (d.label = 'ALT' AND le.valuenum > 40)
    )
  GROUP BY
    d.label
)

SELECT * FROM critical_labs_p90
UNION ALL
SELECT * FROM critical_labs_general;