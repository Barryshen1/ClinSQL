WITH lgib_by_admission AS (
  -- Identify admissions with LGIB diagnoses and whether LGIB is primary (seq_num=1) or only secondary (seq_num>1)
  SELECT
    di.hadm_id,
    di.subject_id,
    MAX(CASE
          WHEN di.seq_num = 1
           AND REGEXP_CONTAINS(LOWER(d.long_title),
                r'gastrointestinal hemorrhag|lower gastrointestinal|rectal hemorrhag|hematochezia|melena')
          THEN 1 ELSE 0 END) AS is_lgib_primary,
    MAX(CASE
          WHEN di.seq_num > 1
           AND REGEXP_CONTAINS(LOWER(d.long_title),
                r'gastrointestinal hemorrhag|lower gastrointestinal|rectal hemorrhag|hematochezia|melena')
          THEN 1 ELSE 0 END) AS is_lgib_secondary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id, di.subject_id
),

imaging_events_per_admission AS (
  -- Count CT / radiography events per hadm_id from hcpcsevents and procedures_icd (via d_icd_procedures)
  -- Use descriptive text matching for CT/computed tomography and radiograph/x-ray
  SELECT
    hadm_id,
    COUNT(*) AS imaging_count
  FROM (
    -- HCPCS/CPT-style events
    SELECT
      hadm_id,
      chartdate,
      short_description
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE LOWER(COALESCE(short_description, '')) LIKE '%ct%'
       OR LOWER(COALESCE(short_description, '')) LIKE '%computed tomography%'
       OR LOWER(COALESCE(short_description, '')) LIKE '%radiograph%'
       OR LOWER(COALESCE(short_description, '')) LIKE '%x-ray%'
       OR LOWER(COALESCE(short_description, '')) LIKE '%xray%'

    UNION ALL

    -- ICD procedure descriptions that indicate CT/radiography
    SELECT
      p.hadm_id,
      p.chartdate,
      dp.long_title AS short_description
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
    WHERE REGEXP_CONTAINS(LOWER(COALESCE(dp.long_title, '')),
          r'computed tomography|ct|radiograph|x-?ray|xray')
  ) ev
  GROUP BY hadm_id
)

SELECT
  -- LOS group: '1-3' or '4-7' days
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
    ELSE NULL
  END AS los_group,
  diagnosis_role,
  COUNT(*) AS admissions_in_group,
  ROUND(AVG(imaging_count), 3) AS mean_imaging_per_admission
FROM (
  -- Base admissions filtered to target cohort (female, age 71-81) and LOS 1-7 days,
  -- and restricting to admissions that have LGIB as either primary or secondary diagnosis.
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    -- determine diagnosis role: primary if is_lgib_primary = 1, else if is_lgib_secondary = 1 then 'secondary'
    CASE
      WHEN l.is_lgib_primary = 1 THEN 'primary'
      WHEN l.is_lgib_primary = 0 AND l.is_lgib_secondary = 1 THEN 'secondary'
      ELSE NULL
    END AS diagnosis_role,
    COALESCE(ie.imaging_count, 0) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN lgib_by_admission l
    ON a.hadm_id = l.hadm_id
  LEFT JOIN imaging_events_per_admission ie
    ON a.hadm_id = ie.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    -- require discharge/admit times present
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- restrict LOS to 1-7 days for downstream grouping (we'll only keep 1-3 and 4-7)
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
    -- require LGIB either primary or secondary
    AND (l.is_lgib_primary = 1 OR l.is_lgib_secondary = 1)
) adm
WHERE diagnosis_role IS NOT NULL
  -- Only keep the two LOS bins asked for
  AND los_days BETWEEN 1 AND 7
GROUP BY los_group, diagnosis_role
ORDER BY los_group, diagnosis_role;