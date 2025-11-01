with an ICH diagnosis and an ICU stay followed by a non-ICU transfer.
WITH ich_admissions AS (
  -- admissions (hadm_id) with an ICH diagnosis by textual match of diagnosis description
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code
   AND d.icd_version = di.icd_version
  WHERE LOWER(di.long_title) LIKE '%hemorrhag%' 
    AND (
      LOWER(di.long_title) LIKE '%intracranial%' OR
      LOWER(di.long_title) LIKE '%intracerebr%' OR
      LOWER(di.long_title) LIKE '%subarachnoid%' OR
      LOWER(di.long_title) LIKE '%subdural%' OR
      LOWER(di.long_title) LIKE '%epidural%'
    )
),
icu_out_transfers AS (
  -- ICU stays that are followed by a transfer into a non-ICU careunit (heuristic)
  SELECT DISTINCT icu.hadm_id, icu.subject_id, icu.intime AS icu_intime, icu.outtime AS icu_outtime, t.intime AS transfer_intime, t.careunit
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t
    ON icu.hadm_id = t.hadm_id
  WHERE icu.outtime IS NOT NULL
    -- transfer recorded at or after ICU outtime (transfer off ICU)
    AND t.intime >= icu.outtime
    -- exclude transfers whose careunit name contains 'ICU' (heuristic)
    AND t.careunit IS NOT NULL
    AND LOWER(t.careunit) NOT LIKE '%icu%'
),
index_cohort AS (
  -- Pick the earliest qualifying admission per subject to represent the patient once
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime AS admit_deathtime,
    p.dod AS patient_dod,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- admission must have an ICH diagnosis
  JOIN ich_admissions iad
    ON a.hadm_id = iad.hadm_id
  -- admission must have an ICU stay with a non-ICU transfer afterward
  JOIN icu_out_transfers iot
    ON a.hadm_id = iot.hadm_id
   AND a.subject_id = iot.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),
cohort_index_admission AS (
  -- keep the first qualifying admission per subject
  SELECT * EXCEPT (rn)
  FROM index_cohort
  WHERE rn = 1
),
flags AS (
  -- compute AKI, ARDS, Sepsis flags (by diagnosis codes/text) for each index admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.admit_deathtime,
    c.patient_dod,
    -- death time preference: in-admission deathtime then patient.dod
    COALESCE(c.admit_deathtime, CAST(c.patient_dod AS TIMESTAMP)) AS death_time,
    -- AKI detection: ICD-10 N17* or ICD-9 584* OR textual match in diagnosis description
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
       AND d.icd_version = di.icd_version
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'n17%')
          OR (d.icd_version = 9  AND LOWER(d.icd_code) LIKE '584%')
          OR LOWER(di.long_title) LIKE '%acute kidney%'
          OR LOWER(di.long_title) LIKE '%acute renal failure%'
        )
      LIMIT 1
    ) AS aki,
    -- ARDS detection: ICD-10 J80 or textual match
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
       AND d.icd_version = di.icd_version
      WHERE d.hadm_id = c.hadm_id
        AND (
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'j80%')
          OR LOWER(di.long_title) LIKE '%acute respiratory distress%'
          OR LOWER(di.long_title) LIKE '%ards%'
        )
      LIMIT 1
    ) AS ards,
    -- Sepsis detection: textual match or common sepsis codes (text match is primary)
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
       AND d.icd_version = di.icd_version
      WHERE d.hadm_id = c.hadm_id
        AND (
          LOWER(di.long_title) LIKE '%sepsis%'
        )
      LIMIT 1
    ) AS sepsis
  FROM cohort_index_admission c
),
scored AS (
  -- compute composite score and death/ survival metrics per patient
  SELECT
    f.*,
    -- convert boolean flags to integers (IF(flag,1,0)) and sum
    (IF(f.aki, 1, 0) + IF(f.ards, 1, 0) + IF(f.sepsis, 1, 0)) AS composite_score,
    -- death within 30 days of admission
    CASE
      WHEN f.death_time IS NOT NULL
        AND TIMESTAMP_DIFF(f.death_time, f.admittime, DAY) BETWEEN 0 AND 30 THEN 1
      ELSE 0
    END AS death_within_30d,
    -- days from admission to death for decedents (non-negative)
    CASE
      WHEN f.death_time IS NOT NULL AND TIMESTAMP_DIFF(f.death_time, f.admittime, SECOND) >= 0
        THEN TIMESTAMP_DIFF(f.death_time, f.admittime, DAY)
      ELSE NULL
    END AS days_to_death
  FROM flags f
)

SELECT
  -- cohort size (unique patients)
  COUNT(1) AS cohort_size,
  -- 30-day mortality count and rate
  SUM(death_within_30d) AS deaths_within_30d,
  SAFE_DIVIDE(SUM(death_within_30d), COUNT(1)) AS mortality_30d_rate,
  -- AKI and ARDS counts and rates
  SUM(CASE WHEN aki THEN 1 ELSE 0 END) AS aki_count,
  SAFE_DIVIDE(SUM(CASE WHEN aki THEN 1 ELSE 0 END), COUNT(1)) AS aki_rate,
  SUM(CASE WHEN ards THEN 1 ELSE 0 END) AS ards_count,
  SAFE_DIVIDE(SUM(CASE WHEN ards THEN 1 ELSE 0 END), COUNT(1)) AS ards_rate,
  -- Composite score percentiles (25th/50th/75th) using APPROX_QUANTILES:
  -- APPROX_QUANTILES(..., 4) returns 5 quantiles: [min, Q1, median, Q3, max]
  APPROX_QUANTILES(composite_score, 4)[OFFSET(1)] AS composite_q25,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(2)] AS composite_q50,
  APPROX_QUANTILES(composite_score, 4)[OFFSET(3)] AS composite_q75,
  -- Median survival among decedents (days). Use APPROX_QUANTILES with n=2 -> [min, median, max].
  -- We compute this only among rows with non-null days_to_death.
  (SELECT
     CASE
       WHEN COUNT(1) = 0 THEN NULL
       ELSE APPROX_QUANTILES(days_to_death, 2)[OFFSET(1)]
     END
   FROM scored s2
   WHERE s2.days_to_death IS NOT NULL
  ) AS median_survival_days_among_decedents
FROM scored;