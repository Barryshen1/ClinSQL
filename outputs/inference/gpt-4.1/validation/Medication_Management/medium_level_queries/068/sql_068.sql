WITH
-- 1. Get ICD codes for T2DM and HF
t2dm_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 E11.* (T2DM)
    (icd_version = 10 AND icd_code LIKE 'E11%')
    -- ICD-9 250.00–250.93, fifth digit 0 or 2 (T2DM)
    OR (icd_version = 9 AND icd_code LIKE '250.%'
        AND SUBSTR(icd_code, 6, 1) IN ('0','2'))
),
hf_icds AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 I50.* (HF)
    (icd_version = 10 AND icd_code LIKE 'I50%')
    -- ICD-9 428.* (HF)
    OR (icd_version = 9 AND icd_code LIKE '428%')
),

-- 2. Find admissions with both T2DM and HF
admissions_with_t2dm_hf AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Age/gender filter
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND a.hadm_id IN (
      -- Must have T2DM
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN t2dm_icds t ON d.icd_code = t.icd_code AND d.icd_version = t.icd_version
    )
    AND a.hadm_id IN (
      -- Must have HF
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN hf_icds h ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
    )
),

-- 3. Get insulin administrations in first 48h and final 12h
insulin_emar AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(e.medication) AS medication,
    LOWER(e.event_txt) AS event_txt
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  WHERE
    -- Only insulin medications
    LOWER(e.medication) LIKE '%insulin%'
),

-- 4. Classify insulin type per administration
classified_insulin AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.charttime,
    CASE
      WHEN REGEXP_CONTAINS(i.medication, r'(glargine|detemir|degludec|nph|basal)') THEN 'basal'
      WHEN REGEXP_CONTAINS(i.medication, r'(aspart|lispro|glulisine|regular|bolus|humalog|novolog|apidra)') THEN 'bolus'
      WHEN REGEXP_CONTAINS(i.event_txt, r'sliding') OR REGEXP_CONTAINS(i.medication, r'sliding') THEN 'sliding_scale'
      ELSE 'other'
    END AS insulin_type
  FROM insulin_emar i
),

-- 5. For each admission, determine regimen(s) in first 48h and final 12h
regimen_by_window AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- First 48h window
    ARRAY_AGG(DISTINCT CASE
      WHEN c.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
        AND insulin_type IN ('basal','bolus','sliding_scale')
      THEN insulin_type
      ELSE NULL
    END) AS first48_types,
    -- Final 12h window
    ARRAY_AGG(DISTINCT CASE
      WHEN c.charttime BETWEEN DATETIME_SUB(a.dischtime, INTERVAL 12 HOUR) AND a.dischtime
        AND insulin_type IN ('basal','bolus','sliding_scale')
      THEN insulin_type
      ELSE NULL
    END) AS final12_types
  FROM admissions_with_t2dm_hf a
  LEFT JOIN classified_insulin c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),

-- 6. Assign regimen per window (basal, bolus, basal-bolus, sliding-scale)
regimen_summary AS (
  SELECT
    subject_id,
    hadm_id,
    -- First 48h
    CASE
      WHEN ARRAY_LENGTH(first48_types) = 0 THEN 'none'
      WHEN 'basal' IN UNNEST(first48_types) AND 'bolus' IN UNNEST(first48_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(first48_types) THEN 'basal_bolus_sliding_scale'
          ELSE 'basal_bolus'
        END
      WHEN 'basal' IN UNNEST(first48_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(first48_types) THEN 'basal_sliding_scale'
          ELSE 'basal'
        END
      WHEN 'bolus' IN UNNEST(first48_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(first48_types) THEN 'bolus_sliding_scale'
          ELSE 'bolus'
        END
      WHEN 'sliding_scale' IN UNNEST(first48_types) THEN 'sliding_scale'
      ELSE 'other'
    END AS first48_regimen,
    -- Final 12h
    CASE
      WHEN ARRAY_LENGTH(final12_types) = 0 THEN 'none'
      WHEN 'basal' IN UNNEST(final12_types) AND 'bolus' IN UNNEST(final12_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(final12_types) THEN 'basal_bolus_sliding_scale'
          ELSE 'basal_bolus'
        END
      WHEN 'basal' IN UNNEST(final12_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(final12_types) THEN 'basal_sliding_scale'
          ELSE 'basal'
        END
      WHEN 'bolus' IN UNNEST(final12_types) THEN
        CASE
          WHEN 'sliding_scale' IN UNNEST(final12_types) THEN 'bolus_sliding_scale'
          ELSE 'bolus'
        END
      WHEN 'sliding_scale' IN UNNEST(final12_types) THEN 'sliding_scale'
      ELSE 'other'
    END AS final12_regimen
  FROM regimen_by_window
),

-- 7. Aggregate counts and percentages
counts AS (
  SELECT
    first48_regimen,
    COUNT(*) AS first48_count
  FROM regimen_summary
  GROUP BY first48_regimen
),
counts_final AS (
  SELECT
    final12_regimen,
    COUNT(*) AS final12_count
  FROM regimen_summary
  GROUP BY final12_regimen
),
total AS (
  SELECT COUNT(*) AS total_count FROM regimen_summary
),

-- 8. Combine and calculate net change
combined AS (
  SELECT
    c.first48_regimen AS regimen,
    c.first48_count,
    cf.final12_count,
    t.total_count,
    ROUND(100.0 * c.first48_count / t.total_count, 1) AS pct_first48,
    ROUND(100.0 * cf.final12_count / t.total_count, 1) AS pct_final12,
    ROUND(100.0 * (cf.final12_count - c.first48_count) / t.total_count, 1) AS pct_net_change
  FROM counts c
  LEFT JOIN counts_final cf ON c.first48_regimen = cf.final12_regimen
  CROSS JOIN total t
)

SELECT
  regimen,
  first48_count,
  pct_first48,
  final12_count,
  pct_final12,
  pct_net_change
FROM combined
ORDER BY regimen;