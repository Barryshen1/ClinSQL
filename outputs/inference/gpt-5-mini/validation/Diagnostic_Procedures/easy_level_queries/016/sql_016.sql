WITH cohort AS (
  -- female patients aged 75-85 at anchor_age, with their hospital admissions
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

per_hadm_ecg_counts AS (
  -- count distinct ECG/telemetry HCPCS codes per hospitalization (include zero by left join)
  SELECT
    c.hadm_id,
    COUNT(DISTINCT
      CASE
        WHEN REGEXP_CONTAINS(
               LOWER(COALESCE(h.short_description, d.long_description, d.short_description, '')),
               r'(ecg|ekg|telemetry|telemet|cardiac monitor|rhythm strip|heart monitor)'
             )
        THEN h.hcpcs_cd
        ELSE NULL
      END
    ) AS num_distinct_ecg_hcpcs
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON c.hadm_id = h.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  GROUP BY c.hadm_id
)

SELECT
  -- approximate 75th percentile of distinct ECG/telemetry procedures per hospitalization
  APPROX_QUANTILES(num_distinct_ecg_hcpcs, 100)[OFFSET(75)] AS p75_distinct_ecg_telemetry_per_hadm
FROM per_hadm_ecg_counts;