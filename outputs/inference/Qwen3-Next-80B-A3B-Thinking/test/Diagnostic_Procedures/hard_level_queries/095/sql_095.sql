WITH target_group AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND i.hadm_id IN (
      SELECT diag.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
      WHERE d.long_title LIKE '%Pulmonary embolism%'
    )
),

chart_events AS (
  SELECT
    c.stay_id,
    COUNT(*) AS chart_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON c.stay_id = i.stay_id
  WHERE c.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),

lab_events AS (
  SELECT
    l.hadm_id,
    COUNT(*) AS lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.hadm_id = i.hadm_id
  WHERE l.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 24 HOUR)
  GROUP BY l.hadm_id
),

diagnostic_score AS (
  SELECT
    t.stay_id,
    t.hadm_id,
    COALESCE(c.chart_count, 0) + COALESCE(l.lab_count, 0) AS diagnostic_score
  FROM target_group t
  LEFT JOIN chart_events c ON t.stay_id = c.stay_id
  LEFT JOIN lab_events l ON t.hadm_id = l.hadm_id
),

target_stats AS (
  SELECT
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ds.diagnostic_score) AS percentile_75,
    AVG(i.los) AS target_los,
    AVG(a.hospital_expire_flag) AS target_mortality
  FROM diagnostic_score ds
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ds.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ds.hadm_id = a.hadm_id
),

general_stats AS (
  SELECT
    AVG(i.los) AS general_los,
    AVG(a.hospital_expire_flag) AS general_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

SELECT
  ts.percentile_75,
  ts.target_los,
  gs.general_los,
  ts.target_mortality,
  gs.general_mortality
FROM target_stats ts, general_stats gs;