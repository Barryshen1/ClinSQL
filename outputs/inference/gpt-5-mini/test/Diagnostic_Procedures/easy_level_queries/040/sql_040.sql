WITH male_cohort AS (
  -- males aged 51-61 inclusive
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 51 AND 61
),
hcpcs_ecg AS (
  -- HCPCS billed procedures that look like ECG/telemetry
  SELECT
    he.subject_id,
    CONCAT('hcpcs_', COALESCE(SAFE_CAST(he.hcpcs_cd AS STRING), '')) AS proc_code
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` he
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON he.hcpcs_cd = d.code
  WHERE (
      LOWER(COALESCE(he.short_description, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%telemet%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%telemet%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(he.short_description, '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(d.long_description, '')) LIKE '%cardiac monitor%'
    )
    -- only interested in subjects in our cohort (optional pre-filter to reduce work)
    AND he.subject_id IN (SELECT subject_id FROM male_cohort)
),
icu_procedure_ecg AS (
  -- ICU procedureevents whose d_items.label indicates ECG/telemetry
  SELECT
    pe.subject_id,
    CONCAT('item_', CAST(pe.itemid AS STRING)) AS proc_code
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE (
      LOWER(COALESCE(di.label, '')) LIKE '%ecg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%ekg%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%telemet%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%telemetry%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%cardiac monitor%'
      OR LOWER(COALESCE(SAFE_CAST(pe.value AS STRING), '')) LIKE '%telemetry%'
    )
    AND pe.subject_id IN (SELECT subject_id FROM male_cohort)
),
-- union distinct procedure codes per subject across both sources
subject_proc_distinct AS (
  SELECT DISTINCT subject_id, proc_code
  FROM (
    SELECT * FROM hcpcs_ecg
    UNION ALL
    SELECT * FROM icu_procedure_ecg
  )
),
-- per-subject distinct-procedure counts, include zeros for patients with no matches
subject_counts AS (
  SELECT
    m.subject_id,
    COALESCE(cnt.num_procs, 0) AS distinct_ecg_telemetry_proc_count
  FROM male_cohort m
  LEFT JOIN (
    SELECT subject_id, COUNT(*) AS num_procs
    FROM subject_proc_distinct
    GROUP BY subject_id
  ) cnt
  ON m.subject_id = cnt.subject_id
)
-- final: compute 25th percentile (approximate)
SELECT
  APPROX_QUANTILES(distinct_ecg_telemetry_proc_count, 100)[OFFSET(25)] AS pct_25_distinct_ecg_telemetry_procs_per_patient,
  COUNT(*) AS cohort_size
FROM subject_counts;