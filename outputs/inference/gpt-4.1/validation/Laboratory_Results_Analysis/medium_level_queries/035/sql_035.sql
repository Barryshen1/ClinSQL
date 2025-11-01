WITH troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

acs_admissions AS (
  -- Identify ACS admissions by ICD codes (ICD-9: 410, 411; ICD-10: I20, I21, I22, I24)
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE (
    (diag.icd_version = 9 AND (
      diag.icd_code LIKE '410%' OR  -- Acute MI
      diag.icd_code LIKE '411%'     -- Unstable angina/other ACS
    )) OR
    (diag.icd_version = 10 AND (
      diag.icd_code LIKE 'I20%' OR  -- Unstable angina
      diag.icd_code LIKE 'I21%' OR  -- Acute MI
      diag.icd_code LIKE 'I22%' OR  -- Subsequent MI
      diag.icd_code LIKE 'I24%'     -- Other ACS
    ))
  )
),

initial_elevated_troponin AS (
  -- For each admission, get the first Troponin T lab and check if it's elevated
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.ref_range_upper
  FROM (
    SELECT
      l.subject_id,
      l.hadm_id,
      l.charttime,
      l.valuenum,
      l.ref_range_upper,
      ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN troponin_t_items tti ON l.itemid = tti.itemid
    WHERE l.valuenum IS NOT NULL
  ) l
  WHERE l.rn = 1 AND l.valuenum > IFNULL(l.ref_range_upper, 0)
),

cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN acs_admissions acs
    ON adm.hadm_id = acs.hadm_id
  JOIN initial_elevated_troponin tro
    ON adm.hadm_id = tro.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 73 AND 83
)

SELECT
  COUNT(*) AS cohort_size,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24), 2) AS avg_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS in_hospital_mortality_percent
FROM cohort;