with an ICH diagnosis,
-- then stratify by a simple composite risk score (sum of 4 comorbidity flags),
-- assign quartiles (NTILE) and report counts, mortality, complication rates, and median LOS for survivors.
WITH ich_seed AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
    AND dd.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND (
      LOWER(dd.long_title) LIKE '%intracerebral%' OR
      LOWER(dd.long_title) LIKE '%subarachnoid%' OR
      (
        LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrag%'
      ) OR
      (LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrag%')
    )
),

-- aggregate diagnoses per admission to compute comorbidity flags and complication flags
hadm_diag_flags AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%hypertension%' THEN 1 ELSE 0 END) AS has_htn,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_dm,
    MAX(CASE WHEN (
          LOWER(dd.long_title) LIKE '%heart failure%' OR
          LOWER(dd.long_title) LIKE '%congestive%' OR
          LOWER(dd.long_title) LIKE '%ischemic heart%' OR
          LOWER(dd.long_title) LIKE '%coronar%' OR
          LOWER(dd.long_title) LIKE '%myocardial%'
        ) THEN 1 ELSE 0 END) AS has_cardio_history,
    MAX(CASE WHEN (
          LOWER(dd.long_title) LIKE '%coagulop%' OR
          LOWER(dd.long_title) LIKE '%coagulation%' OR
          LOWER(dd.long_title) LIKE '%bleeding disorder%' OR
          LOWER(dd.long_title) LIKE '%coagulable%'
        ) THEN 1 ELSE 0 END) AS has_coag,
    -- cardiac complication flag (broad text-match)
    MAX(CASE WHEN (
          LOWER(dd.long_title) LIKE '%myocardial%' OR
          LOWER(dd.long_title) LIKE '%arrhythmia%' OR
          LOWER(dd.long_title) LIKE '%cardiac arrest%'
        ) THEN 1 ELSE 0 END) AS has_cardiac_comp,
    -- neurologic complication flag: match neurologic complication terms but exclude index ICH labels
    MAX(CASE WHEN (
          (
            LOWER(dd.long_title) LIKE '%seizure%' OR
            LOWER(dd.long_title) LIKE '%stroke%' OR
            LOWER(dd.long_title) LIKE '%hemiplegia%' OR
            LOWER(dd.long_title) LIKE '%hydrocephalus%' OR
            LOWER(dd.long_title) LIKE '%neurologic%' OR
            LOWER(dd.long_title) LIKE '%neurological%'
          )
          AND NOT (
            LOWER(dd.long_title) LIKE '%intracerebral%' OR
            LOWER(dd.long_title) LIKE '%subarachnoid%' OR
            (
              LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrag%'
            ) OR
            (LOWER(dd.long_title) LIKE '%intracranial%' AND LOWER(dd.long_title) LIKE '%hemorrag%')
          )
        ) THEN 1 ELSE 0 END) AS has_neuro_comp
  FROM ich_seed s
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON di.hadm_id = s.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON dd.icd_code = di.icd_code
    AND dd.icd_version = di.icd_version
  GROUP BY
    s.subject_id, s.hadm_id, s.admittime, s.dischtime, s.hospital_expire_flag
),

-- compute composite score and LOS (days)
hadm_scores AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    has_htn,
    has_dm,
    has_cardio_history,
    has_coag,
    has_cardiac_comp,
    has_neuro_comp,
    -- composite score: sum of 4 comorbidity flags
    (SAFE_CAST(has_htn AS INT64) + SAFE_CAST(has_dm AS INT64) + SAFE_CAST(has_cardio_history AS INT64) + SAFE_CAST(has_coag AS INT64)) AS composite_score,
    -- LOS in days (fractional)
    (TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0) AS los_days
  FROM hadm_diag_flags
),

-- assign quartiles (1 = highest composite score)
hadm_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY composite_score DESC) AS quartile
  FROM hadm_scores
)

-- final aggregation per quartile
SELECT
  quartile,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(1) AS admission_count,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS mortality_rate,
  SUM(CASE WHEN has_cardiac_comp = 1 THEN 1 ELSE 0 END) AS cardiac_complication_count,
  SAFE_DIVIDE(SUM(CASE WHEN has_cardiac_comp = 1 THEN 1 ELSE 0 END), COUNT(1)) AS cardiac_complication_rate,
  SUM(CASE WHEN has_neuro_comp = 1 THEN 1 ELSE 0 END) AS neurologic_complication_count,
  SAFE_DIVIDE(SUM(CASE WHEN has_neuro_comp = 1 THEN 1 ELSE 0 END), COUNT(1)) AS neurologic_complication_rate,
  -- median LOS among survivors in days (approximate). We pass NULL for non-survivors so they're excluded.
  APPROX_QUANTILES(IF(hospital_expire_flag = 0, los_days, NULL), 2)[OFFSET(1)] AS median_los_days_survivors
FROM hadm_quartiles
GROUP BY quartile
ORDER BY quartile;