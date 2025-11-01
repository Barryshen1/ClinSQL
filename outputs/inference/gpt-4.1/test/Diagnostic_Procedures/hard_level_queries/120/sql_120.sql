WITH cohort AS (
  -- Identify male ICU patients aged 74–84 with upper GI bleeding, first ICU stay only
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    p.anchor_age,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  -- Only first ICU stay per patient
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND i.stay_id = (
      SELECT MIN(stay_id)
      FROM physionet-data.mimiciv_3_1_icu.icustays
      WHERE subject_id = p.subject_id
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 codes for upper GI bleeding
          (d.icd_version = 10 AND (
            REGEXP_CONTAINS(d.icd_code, r'^K92[012]$') OR
            REGEXP_CONTAINS(d.icd_code, r'^K25[4-6]$') OR
            REGEXP_CONTAINS(d.icd_code, r'^K26[4-6]$') OR
            REGEXP_CONTAINS(d.icd_code, r'^K27[4-6]$') OR
            REGEXP_CONTAINS(d.icd_code, r'^K28[4-6]$') OR
            REGEXP_CONTAINS(d.icd_code, r'^I85[01]$')
          ))
          -- ICD-9 codes for upper GI bleeding
          OR (d.icd_version = 9 AND (
            REGEXP_CONTAINS(d.icd_code, r'^578') OR -- GI hemorrhage
            REGEXP_CONTAINS(d.icd_code, r'^530\.7$') OR -- esophageal varices with bleeding
            REGEXP_CONTAINS(d.icd_code, r'^531[0-4]$') OR -- gastric ulcer with hemorrhage
            REGEXP_CONTAINS(d.icd_code, r'^532[0-4]$') OR -- duodenal ulcer with hemorrhage
            REGEXP_CONTAINS(d.icd_code, r'^533[0-4]$') OR -- peptic ulcer with hemorrhage
            REGEXP_CONTAINS(d.icd_code, r'^534[0-4]$')    -- gastrojejunal ulcer with hemorrhage
          ))
        )
    )
),

diagnostic_events AS (
  -- Count diagnostic events in first 72h of ICU stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    -- Labs
    COUNT(DISTINCT l.labevent_id) AS lab_count,
    -- Microbiology
    COUNT(DISTINCT m.microevent_id) AS micro_count,
    -- Diagnostic procedures (ICD)
    COUNT(DISTINCT pr.icd_code) AS proc_count
  FROM cohort c
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents l
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.icu_intime
    AND l.charttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.microbiologyevents m
    ON c.hadm_id = m.hadm_id
    AND m.charttime >= c.icu_intime
    AND m.charttime < DATETIME_ADD(c.icu_intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON c.hadm_id = pr.hadm_id
    AND pr.chartdate >= DATE(c.icu_intime)
    AND pr.chartdate < DATE_ADD(DATE(c.icu_intime), INTERVAL 3 DAY)
    AND (
      -- ICD-10-PCS diagnostic procedures: codes starting with '0' and 3rd char in [2,3,4,5,6,7,8]
      (pr.icd_version = 10 AND REGEXP_CONTAINS(pr.icd_code, r'^0[0-9][2-8]'))
      -- ICD-9-CM diagnostic procedures: code ranges 87–99 (radiology, diagnostic)
      OR (pr.icd_version = 9 AND CAST(SUBSTR(pr.icd_code, 1, 2) AS INT64) BETWEEN 87 AND 99)
    )
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),

diagnostic_intensity AS (
  -- Sum up all diagnostic events per patient
  SELECT
    d.subject_id,
    d.hadm_id,
    d.stay_id,
    COALESCE(d.lab_count, 0) + COALESCE(d.micro_count, 0) + COALESCE(d.proc_count, 0) AS diag_count
  FROM diagnostic_events d
),

final_cohort AS (
  -- Merge diagnostic intensity with cohort and calculate LOS
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    di.diag_count,
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND), 86400) AS hosp_los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN diagnostic_intensity di
    ON c.subject_id = di.subject_id
    AND c.hadm_id = di.hadm_id
    AND c.stay_id = di.stay_id
),

quartiles AS (
  -- Assign quartiles based on diagnostic intensity
  SELECT
    *,
    NTILE(4) OVER (ORDER BY diag_count) AS diag_quartile
  FROM final_cohort
)

SELECT
  diag_quartile,
  COUNT(*) AS n_patients,
  ROUND(AVG(diag_count), 2) AS mean_procedure_count,
  ROUND(AVG(hosp_los), 2) AS mean_hospital_los_days,
  ROUND(AVG(hospital_expire_flag), 3) AS in_hospital_mortality_rate
FROM quartiles
GROUP BY diag_quartile
ORDER BY diag_quartile;