WITH ards_icu AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND (
      LOWER(dd.long_title) LIKE '%acute respiratory distress%'
      OR d.icd_code = 'J80'
    )
),
ards_procedures AS (
  SELECT
    a.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM ards_icu a
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON a.stay_id = pe.stay_id
    AND pe.starttime >= a.intime
    AND pe.starttime < a.intime + INTERVAL '24 hours'
  GROUP BY a.stay_id
),
general_icu AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
),
general_procedures AS (
  SELECT
    g.stay_id,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM general_icu g
  LEFT JOIN physionet-data.mimiciv_3_1_icu.procedureevents pe
    ON g.stay_id = pe.stay_id
    AND pe.starttime >= g.intime
    AND pe.starttime < g.intime + INTERVAL '24 hours'
  GROUP BY g.stay_id
),
ards_summary AS (
  SELECT
    'ARDS' AS group_label,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ap.procedure_count) AS p25_procedures,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ap.procedure_count) AS p75_procedures,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ap.procedure_count) AS p95_procedures,
    AVG(DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 3600.0 / 24.0) AS avg_hospital_los,
    AVG(a.hospital_expire_flag) AS avg_hospital_mortality
  FROM ards_icu a
  LEFT JOIN ards_procedures ap ON a.stay_id = ap.stay_id
  GROUP BY group_label
),
general_summary AS (
  SELECT
    'General ICU' AS group_label,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY gp.procedure_count) AS p25_procedures,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gp.procedure_count) AS p75_procedures,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gp.procedure_count) AS p95_procedures,
    AVG(DATETIME_DIFF(g.dischtime, g.admittime, SECOND) / 3600.0 / 24.0) AS avg_hospital_los,
    AVG(g.hospital_expire_flag) AS avg_hospital_mortality
  FROM general_icu g
  LEFT JOIN general_procedures gp ON g.stay_id = gp.stay_id
  GROUP BY group_label
)
SELECT * FROM ards_summary
UNION ALL
SELECT * FROM general_summary
ORDER BY group_label;