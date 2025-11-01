WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code = '78552') 
          OR (diag.icd_version = 10 AND diag.icd_code = 'R6521')
        )
    )
),

filtered_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(dischtime, admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM base_admissions
  WHERE age_admit BETWEEN 57 AND 67
    AND DATE_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 7
),

admissions_with_icu AS (
  SELECT 
    fa.*,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 'ICU' ELSE 'no ICU' END AS icu_group
  FROM filtered_admissions fa
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu ON fa.hadm_id = icu.hadm_id
),

us_procedures AS (
  -- ICD Procedures (Ultrasound/Echo)
  SELECT 
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%ultrasound%' 
    OR LOWER(d.long_title) LIKE '%echocardiogram%'

  UNION ALL

  -- HCPCS Procedures (Ultrasound/Echo)
  SELECT 
    h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE 
    LOWER(d.long_description) LIKE '%ultrasound%' 
    OR LOWER(d.long_description) LIKE '%echocardiogram%'
),

us_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS us_count
  FROM us_procedures
  GROUP BY hadm_id
),

admission_us AS (
  SELECT 
    a.hadm_id,
    a.los_group,
    a.icu_group,
    COALESCE(u.us_count, 0) AS us_count
  FROM admissions_with_icu a
  LEFT JOIN us_counts u
    ON a.hadm_id = u.hadm_id
)

SELECT 
  los_group,
  icu_group,
  APPROX_QUANTILES(us_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(us_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(us_count, 100)[OFFSET(75)] AS p75
FROM admission_us
GROUP BY los_group, icu_group
ORDER BY los_group, icu_group;