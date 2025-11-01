WITH cohort AS (
  -- Select admissions meeting criteria
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.admission_type,
    srv.curr_service,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  LEFT JOIN (
    -- Get first service per admission (curr_service at admission)
    SELECT
      hadm_id,
      curr_service
    FROM (
      SELECT
        hadm_id,
        curr_service,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.services`
    )
    WHERE rn = 1
  ) srv
    ON adm.hadm_id = srv.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND adm.admission_type = 'EMERGENCY'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) >= 0
    -- Medical services only (exclude surgical)
    AND (
      srv.curr_service LIKE 'MED%'
      OR srv.curr_service LIKE 'CARD%'
      OR srv.curr_service LIKE 'NEURO%'
      OR srv.curr_service LIKE 'ONC%'
      OR srv.curr_service LIKE 'RENAL%'
      OR srv.curr_service LIKE 'ENDO%'
      OR srv.curr_service LIKE 'HEM%'
      OR srv.curr_service LIKE 'PUL%'
      OR srv.curr_service LIKE 'GER%'
      OR srv.curr_service LIKE 'INF%'
      OR srv.curr_service LIKE 'PSYCH%'
      OR srv.curr_service LIKE 'FAM%'
      OR srv.curr_service LIKE 'ALLERGY%'
      OR srv.curr_service LIKE 'GASTRO%'
      OR srv.curr_service LIKE 'ID%'
      OR srv.curr_service LIKE 'RHEUM%'
      OR srv.curr_service LIKE 'DERM%'
      OR srv.curr_service LIKE 'OPHTH%'
      OR srv.curr_service LIKE 'PMR%'
      OR srv.curr_service LIKE 'NEPH%'
      OR srv.curr_service LIKE 'HOSP%'
      -- Add other medical services as needed
    )
)

-- Part 1: Proportion with LOS >=7 days by discharge status
, summary AS (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN hospital_expire_flag = 0 THEN 'Discharged alive'
      ELSE 'Unknown'
    END AS discharge_status,
    COUNTIF(los_days >= 7) AS n_LOS_7plus,
    COUNT(*) AS n_total,
    SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS proportion_LOS_7plus
  FROM cohort
  GROUP BY discharge_status
)

-- Part 2: Percentile rank of 7-day LOS in cohort
, los_percentile AS (
  SELECT
    -- Percentile rank: proportion of patients with LOS <= 7 days
    SAFE_DIVIDE(COUNTIF(los_days <= 7), COUNT(*)) AS percentile_rank_7day
  FROM cohort
)

SELECT
  -- Part 1: Proportion table
  discharge_status,
  n_LOS_7plus,
  n_total,
  proportion_LOS_7plus
FROM summary

UNION ALL

SELECT
  'Percentile rank of 7-day LOS in cohort' AS discharge_status,
  NULL AS n_LOS_7plus,
  NULL AS n_total,
  percentile_rank_7day AS proportion_LOS_7plus
FROM los_percentile
;