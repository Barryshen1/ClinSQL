WITH copd_cohort AS (
  -- Base COPD exacerbation cohort: male, 88-98, ICU stays with J44 diagnosis
  SELECT DISTINCT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'J44%'
    AND d.seq_num = 1  -- Focus on primary diagnosis
    AND i.outtime IS NOT NULL
),

all_matched_cohort AS (
  -- Comparison: all male 88-98 ICU patients (no COPD filter)
  SELECT DISTINCT 
    i.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND i.outtime IS NOT NULL
),

procedure_counts_copd AS (
  -- Distinct procedures in first 72h for COPD cohort
  WITH proc_events AS (
    -- ICU procedureevents
    SELECT 
      c.stay_id,
      COALESCE(di.label, di.abbreviation, CAST(pe.itemid AS STRING)) AS proc_desc
    FROM copd_cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      ON c.subject_id = pe.subject_id
      AND c.hadm_id = pe.hadm_id
      AND c.stay_id = pe.stay_id
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON CAST(pe.itemid AS STRING) = di.itemid
    WHERE pe.starttime >= c.intime
      AND pe.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
      AND pe.itemid IS NOT NULL
      AND (di.label IS NOT NULL OR di.abbreviation IS NOT NULL)

    UNION DISTINCT

    -- ICD procedures (within admission, approx first 72h via chartdate)
    SELECT 
      c.stay_id,
      COALESCE(dip.long_title, CAST(pr.icd_code AS STRING)) AS proc_desc
    FROM copd_cohort c
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
      ON c.hadm_id = pr.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
      ON pr.icd_code = dip.icd_code
      AND pr.icd_version = dip.icd_version
    WHERE pr.chartdate BETWEEN DATE(c.intime) AND DATE(TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR))
      AND pr.icd_code IS NOT NULL
  )
  SELECT 
    stay_id,
    COUNT(DISTINCT proc_desc) AS num_distinct_procs
  FROM proc_events
  GROUP BY stay_id
)

-- COPD metrics
SELECT 
  'COPD Exacerbation Cohort' AS cohort,
  PERCENTILE_CONT(0.75) OVER (ORDER BY COALESCE(num_distinct_procs, 0)) AS p75_distinct_procedures_first_72h,
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS mean_inhospital_mortality
FROM copd_cohort c
LEFT JOIN procedure_counts_copd pc
  ON c.stay_id = pc.stay_id

UNION ALL

-- Comparison metrics (no procedures for comparison cohort)
SELECT 
  'Age-Matched ICU Cohort' AS cohort,
  NULL AS p75_distinct_procedures_first_72h,  -- Not requested for comparison
  AVG(los) AS mean_icu_los_days,
  AVG(hospital_expire_flag) AS mean_inhospital_mortality
FROM all_matched_cohort;