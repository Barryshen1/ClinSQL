WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- join hcpcsevents and d_hcpcs but only mark rows as echo-related when description matches
hcpcps AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hcpcs_cd,
    COALESCE(d.long_description, h.short_description, '') AS desc_text
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
),

-- For each hospitalization in the cohort, count distinct echo-related hcpcs_cd (0 if none)
counts_per_hadm AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT CASE
        WHEN REGEXP_CONTAINS(LOWER(h.desc_text), r'echo|echocardi')
             AND h.hcpcs_cd IS NOT NULL
        THEN h.hcpcs_cd
        ELSE NULL
      END) AS num_distinct_echo_codes
  FROM cohort c
  LEFT JOIN hcpcps h
    ON c.subject_id = h.subject_id
   AND c.hadm_id = h.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),

max_value AS (
  SELECT COALESCE(MAX(num_distinct_echo_codes), 0) AS max_distinct_echo_per_hadm
  FROM counts_per_hadm
)

-- Return the maximum plus the hospitalization(s) that achieve it
SELECT
  m.max_distinct_echo_per_hadm AS max_distinct_echo_procedures_per_hospitalization,
  c.subject_id,
  c.hadm_id,
  c.num_distinct_echo_codes
FROM counts_per_hadm c
CROSS JOIN max_value m
WHERE c.num_distinct_echo_codes = m.max_distinct_echo_per_hadm
ORDER BY c.subject_id, c.hadm_id;