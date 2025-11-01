WITH ich_cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND (
      LOWER(d_diag.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(d_diag.long_title) LIKE '%intracerebral hemorrhage%'
      OR d_diag.icd_code LIKE 'I61%'
      OR d_diag.icd_code LIKE 'I62%'
    )
),
ich_diagnostic_intensity AS (
  SELECT
    ic.stay_id,
    COUNT(DISTINCT le.itemid) +
    COUNT(DISTINCT ce.itemid) +
    COUNT(DISTINCT pe.itemid) AS diagnostic_count
  FROM ich_cohort ic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ic.hadm_id = le.hadm_id
    AND le.charttime >= ic.intime
    AND le.charttime < DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ic.stay_id = ce.stay_id
    AND ce.charttime >= ic.intime
    AND ce.charttime < DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON ic.stay_id = pe.stay_id
    AND pe.starttime >= ic.intime
    AND pe.starttime < DATETIME_ADD(ic.intime, INTERVAL 72 HOUR)
  GROUP BY ic.stay_id
),
ich_stats AS (
  SELECT
    'ICH 56-66F' AS cohort,
    APPROX_QUANTILES(diag.diagnostic_count, 100)[OFFSET(95)] AS diag_intensity_95th,
    AVG(icu.los) AS avg_los,
    AVG(CAST(adm.hospital_expire_flag AS INT)) AS mortality_rate
  FROM ich_diagnostic_intensity diag
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON diag.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),
all_icu_stats AS (
  SELECT
    'All ICU' AS cohort,
    CAST(NULL AS FLOAT64) AS diag_intensity_95th,
    AVG(icu.los) AS avg_los,
    AVG(CAST(adm.hospital_expire_flag AS INT)) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
)
-- Combine results
SELECT * FROM ich_stats
UNION ALL
SELECT * FROM all_icu_stats;