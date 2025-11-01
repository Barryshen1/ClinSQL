WITH resp_failure_patients AS (
  -- Identify ICU stays with respiratory failure diagnosis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    CASE
      WHEN pat.gender = 'M' AND pat.anchor_age BETWEEN 40 AND 50 THEN 'Male_40_50'
      ELSE 'Resp_Failure_All'
    END AS cohort
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON icu.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON icu.hadm_id = diag.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON diag.icd_code = dd.icd_code AND diag.icd_version = dd.icd_version
  WHERE
    (
      -- ICD-10 J96* or ICD-9 518.81, 518.82, 518.84, etc.
      (diag.icd_version = 10 AND diag.icd_code LIKE 'J96%')
      OR (diag.icd_version = 9 AND diag.icd_code IN ('51881','51882','51884'))
    )
),
vitals AS (
  -- Extract relevant vital signs in first 48h of ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN resp_failure_patients rfp ON ce.stay_id = rfp.stay_id
  WHERE
    ce.itemid IN (220045, 211, 220052, 456, 220210, 618, 220277, 646, 223761, 678)
    AND ce.charttime >= rfp.intime
    AND ce.charttime < DATETIME_ADD(rfp.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
),
pivot_vitals AS (
  -- Pivot vital signs per charttime
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    MAX(CASE WHEN itemid IN (220045, 211) THEN valuenum END) AS HR,
    MAX(CASE WHEN itemid IN (220052, 456) THEN valuenum END) AS MAP,
    MAX(CASE WHEN itemid IN (220210, 618) THEN valuenum END) AS RR,
    MAX(CASE WHEN itemid IN (220277, 646) THEN valuenum END) AS SpO2,
    MAX(CASE WHEN itemid IN (223761, 678) THEN valuenum END) AS Temp
  FROM
    vitals
  GROUP BY
    subject_id, hadm_id, stay_id, charttime
),
vii_calc AS (
  -- Calculate Vital Instability Index per charttime
  SELECT
    pv.subject_id,
    pv.hadm_id,
    pv.stay_id,
    pv.charttime,
    -- Binary flags for instability
    IF(HR IS NOT NULL AND (HR > 120 OR HR < 50), 1, 0) AS HR_flag,
    IF(MAP IS NOT NULL AND MAP < 65, 1, 0) AS MAP_flag,
    IF(RR IS NOT NULL AND (RR > 30 OR RR < 8), 1, 0) AS RR_flag,
    IF(SpO2 IS NOT NULL AND SpO2 < 90, 1, 0) AS SpO2_flag,
    IF(Temp IS NOT NULL AND (Temp > 38.5 OR Temp < 35), 1, 0) AS Temp_flag,
    -- VII = sum of flags
    IF(HR IS NOT NULL AND (HR > 120 OR HR < 50), 1, 0)
    + IF(MAP IS NOT NULL AND MAP < 65, 1, 0)
    + IF(RR IS NOT NULL AND (RR > 30 OR RR < 8), 1, 0)
    + IF(SpO2 IS NOT NULL AND SpO2 < 90, 1, 0)
    + IF(Temp IS NOT NULL AND (Temp > 38.5 OR Temp < 35), 1, 0) AS VII,
    -- For burden calculations
    IF(MAP IS NOT NULL AND MAP < 65, 1, 0) AS hypotensive,
    IF(HR IS NOT NULL AND HR > 120, 1, 0) AS tachycardic
  FROM
    pivot_vitals pv
),
agg_per_stay AS (
  -- Aggregate VII and burden per stay
  SELECT
    vii.subject_id,
    vii.hadm_id,
    vii.stay_id,
    COUNT(*) AS n_obs,
    STDDEV_SAMP(vii.VII) AS VII_SD,
    APPROX_QUANTILES(vii.VII, 100)[24] AS VII_25th,
    APPROX_QUANTILES(vii.VII, 100)[49] AS VII_50th,
    APPROX_QUANTILES(vii.VII, 100)[74] AS VII_75th,
    APPROX_QUANTILES(vii.VII, 100)[94] AS VII_95th,
    SAFE_DIVIDE(SUM(vii.hypotensive), COUNT(*)) AS hypotensive_burden,
    SAFE_DIVIDE(SUM(vii.tachycardic), COUNT(*)) AS tachycardic_burden
  FROM
    vii_calc vii
  GROUP BY
    vii.subject_id, vii.hadm_id, vii.stay_id
),
final AS (
  -- Merge with cohort info and ICU LOS/mortality
  SELECT
    rfp.cohort,
    agg.VII_SD,
    agg.VII_25th,
    agg.VII_50th,
    agg.VII_75th,
    agg.VII_95th,
    agg.hypotensive_burden,
    agg.tachycardic_burden,
    rfp.los AS icu_los,
    rfp.hospital_expire_flag AS mortality
  FROM
    agg_per_stay agg
    JOIN resp_failure_patients rfp ON agg.stay_id = rfp.stay_id
)
-- Output summary statistics for each cohort
SELECT
  cohort,
  COUNT(*) AS n_stays,
  SAFE_AVG(VII_SD) AS avg_VII_SD,
  APPROX_QUANTILES(VII_25th, 100)[49] AS median_VII_25th,
  APPROX_QUANTILES(VII_50th, 100)[49] AS median_VII_50th,
  APPROX_QUANTILES(VII_75th, 100)[49] AS median_VII_75th,
  APPROX_QUANTILES(VII_95th, 100)[49] AS median_VII_95th,
  SAFE_AVG(hypotensive_burden) AS avg_hypotensive_burden,
  SAFE_AVG(tachycardic_burden) AS avg_tachycardic_burden,
  SAFE_AVG(icu_los) AS avg_icu_los,
  SAFE_AVG(mortality) AS mortality_rate
FROM
  final
GROUP BY
  cohort
ORDER BY
  cohort;